package com.example.voltstride

import android.Manifest
import android.content.Context
import android.content.ContentValues
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.provider.Settings
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "voltstride/heart_rate"
        private const val EVENT_CHANNEL = "voltstride/heart_rate_events"
        private const val SETTINGS_CHANNEL = "voltstride/android_settings"
        private const val STEP_COUNT_CHANNEL = "voltstride/step_count_events"
        private val HEART_RATE_SERVICE: UUID =
            UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
        private val HEART_RATE_MEASUREMENT: UUID =
            UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
        private val CLIENT_CHARACTERISTIC_CONFIG: UUID =
            UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    private var bluetoothScanner: BluetoothLeScanner? = null
    private var activeScanCallback: ScanCallback? = null
    private var scanTimeout: Runnable? = null
    private var scanResult: MethodChannel.Result? = null
    private val discoveredDevices = linkedMapOf<String, Map<String, Any>>()

    private var activeGatt: BluetoothGatt? = null
    private var pendingConnectResult: MethodChannel.Result? = null
    private var connectTimeout: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidSdkVersion" -> result.success(Build.VERSION.SDK_INT)
                    "scan" -> startHeartRateScan(
                        (call.argument<Int>("durationSeconds") ?: 8).coerceIn(3, 20),
                        result,
                    )
                    "connect" -> {
                        val deviceId = call.argument<String>("deviceId")
                        if (deviceId.isNullOrBlank()) {
                            result.error("invalid_device", "Missing Bluetooth device ID.", null)
                        } else {
                            connectToHeartRateDevice(deviceId, result)
                        }
                    }
                    "disconnect" -> {
                        disconnectHeartRateDevice()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STEP_COUNT_CHANNEL)
            .setStreamHandler(StepCounterStreamHandler(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> openSettings(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(
                            Settings.EXTRA_APP_PACKAGE,
                            packageName,
                        ),
                        result,
                    )
                    "openAppSettings" -> openSettings(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            .setData(Uri.parse("package:$packageName")),
                        result,
                    )
                    "moveTaskToBack" -> result.success(moveTaskToBack(true))
                    "saveFileToDownloads" -> {
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        val bytes = call.argument<ByteArray>("bytes")
                        if (fileName.isNullOrBlank() || bytes == null) {
                            result.error("invalid_file", "Nama file atau isi file tidak tersedia.", null)
                        } else {
                            saveFileToDownloads(fileName, mimeType, bytes, result)
                        }
                    }
                    "scheduleTrainingReminder" -> {
                        try {
                            val id = call.argument<Int>("id")
                            val title = call.argument<String>("title")
                            val category = call.argument<String>("category")
                            val weekdays = call.argument<List<Int>>("weekdays")
                            if (id == null || title.isNullOrBlank() || category.isNullOrBlank() || weekdays.isNullOrEmpty()) {
                                result.error("invalid_reminder", "Data pengingat belum lengkap.", null)
                            } else {
                                ReminderPulseReceiver.schedule(
                                    context = this,
                                    id = id,
                                    title = title,
                                    category = category,
                                    weekdays = weekdays,
                                    hour = call.argument<Int>("hour") ?: 7,
                                    minute = call.argument<Int>("minute") ?: 0,
                                    durationMinutes = call.argument<Int>("durationMinutes") ?: 30,
                                    repeatIntervalSeconds = call.argument<Int>("repeatIntervalSeconds") ?: 60,
                                    doneLabel = call.argument<String>("doneLabel") ?: "Selesai",
                                    bodyLabel = call.argument<String>("bodyLabel") ?: "Pengingat latihan",
                                )
                                result.success(true)
                            }
                        } catch (error: Exception) {
                            result.error("schedule_reminder_failed", error.message ?: "Pengingat gagal dijadwalkan.", null)
                        }
                    }
                    "cancelTrainingReminder" -> {
                        val id = call.argument<Int>("id")
                        if (id == null) {
                            result.error("invalid_reminder", "ID pengingat tidak tersedia.", null)
                        } else {
                            ReminderPulseReceiver.cancel(this, id)
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveFileToDownloads(
        fileName: String,
        mimeType: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        try {
            val safeName = fileName.substringAfterLast('/').substringAfterLast('\\')
                .replace(Regex("[^A-Za-z0-9._-]"), "_")
                .ifBlank { "voltstride-file.bin" }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val relativePath = Environment.DIRECTORY_DOWNLOADS + "/VoltStride"
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: throw IllegalStateException("Penyimpanan Downloads tidak tersedia.")
                contentResolver.openOutputStream(uri)?.use { stream ->
                    stream.write(bytes)
                    stream.flush()
                } ?: throw IllegalStateException("File tidak dapat ditulis.")
                val published = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                contentResolver.update(uri, published, null, null)
                result.success("Downloads/VoltStride/$safeName")
            } else {
                val root = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir
                val directory = File(root, "VoltStride")
                if (!directory.exists() && !directory.mkdirs()) {
                    throw IllegalStateException("Folder penyimpanan tidak dapat dibuat.")
                }
                val file = File(directory, safeName)
                file.writeBytes(bytes)
                result.success(file.absolutePath)
            }
        } catch (error: Exception) {
            result.error("save_file_failed", error.message ?: "File tidak dapat disimpan.", null)
        }
    }

    private fun openSettings(intent: Intent, result: MethodChannel.Result) {
        try {
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error(
                "settings_unavailable",
                error.message ?: "Android settings could not be opened.",
                null,
            )
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun startHeartRateScan(
        durationSeconds: Int,
        result: MethodChannel.Result,
    ) {
        if (!hasBluetoothPermission()) {
            result.error("bluetooth_permission", "Bluetooth scan permission is required.", null)
            return
        }
        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("bluetooth_unsupported", "This device does not support Bluetooth.", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("bluetooth_off", "Turn on Bluetooth and try again.", null)
            return
        }
        if (scanResult != null) {
            result.error("scan_in_progress", "A Bluetooth scan is already in progress.", null)
            return
        }

        val scanner = try {
            adapter.bluetoothLeScanner
        } catch (error: SecurityException) {
            result.error("bluetooth_permission", error.message, null)
            return
        }
        if (scanner == null) {
            result.error("scanner_unavailable", "Bluetooth scanning is unavailable.", null)
            return
        }

        bluetoothScanner = scanner
        discoveredDevices.clear()
        scanResult = result
        val serviceFilter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(HEART_RATE_SERVICE))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device
                val name = try {
                    device.name ?: result.scanRecord?.deviceName ?: "Heart-rate sensor"
                } catch (_: SecurityException) {
                    result.scanRecord?.deviceName ?: "Heart-rate sensor"
                }
                discoveredDevices[device.address] = mapOf(
                    "id" to device.address,
                    "name" to name,
                    "rssi" to result.rssi,
                )
            }

            override fun onScanFailed(errorCode: Int) {
                finishHeartRateScan(
                    errorCode = errorCode,
                    message = "Bluetooth scan failed with code $errorCode.",
                )
            }
        }
        activeScanCallback = callback
        try {
            scanner.startScan(listOf(serviceFilter), settings, callback)
            val timeout = Runnable { finishHeartRateScan() }
            scanTimeout = timeout
            mainHandler.postDelayed(timeout, durationSeconds * 1000L)
        } catch (error: SecurityException) {
            finishHeartRateScan(
                errorCode = -1,
                message = error.message ?: "Bluetooth scan permission is required.",
            )
        } catch (error: Exception) {
            finishHeartRateScan(errorCode = -1, message = error.message ?: "Bluetooth scan failed.")
        }
    }

    private fun finishHeartRateScan(errorCode: Int? = null, message: String? = null) {
        val scanner = bluetoothScanner
        val callback = activeScanCallback
        if (scanner != null && callback != null) {
            try {
                scanner.stopScan(callback)
            } catch (_: Exception) {
                // Hasil pemindaian tetap dapat dikembalikan walau scan sudah berhenti.
            }
        }
        scanTimeout?.let { mainHandler.removeCallbacks(it) }
        scanTimeout = null
        bluetoothScanner = null
        activeScanCallback = null
        val result = scanResult
        scanResult = null
        if (result == null) return
        if (errorCode != null) {
            result.error("scan_failed", message ?: "Bluetooth scan failed.", errorCode)
            return
        }
        result.success(discoveredDevices.values.toList().sortedByDescending {
            it["rssi"] as Int
        })
    }

    private fun connectToHeartRateDevice(
        deviceId: String,
        result: MethodChannel.Result,
    ) {
        if (!hasBluetoothPermission()) {
            result.error("bluetooth_permission", "Bluetooth connection permission is required.", null)
            return
        }
        val adapter = bluetoothAdapter()
        if (adapter == null || !adapter.isEnabled) {
            result.error("bluetooth_off", "Turn on Bluetooth and try again.", null)
            return
        }
        disconnectHeartRateDevice()

        val device = try {
            adapter.getRemoteDevice(deviceId)
        } catch (error: IllegalArgumentException) {
            result.error("invalid_device", "The Bluetooth device ID is invalid.", null)
            return
        } catch (error: SecurityException) {
            result.error("bluetooth_permission", error.message, null)
            return
        }

        pendingConnectResult = result
        connectTimeout = Runnable {
            failPendingConnection("connection_timeout", "The heart-rate sensor did not connect in time.")
        }
        connectTimeout?.let { mainHandler.postDelayed(it, 20_000L) }
        try {
            activeGatt = device.connectGatt(this, false, heartRateGattCallback, BluetoothDevice.TRANSPORT_LE)
            if (activeGatt == null) {
                failPendingConnection("connection_failed", "Android could not start the Bluetooth connection.")
            }
        } catch (error: SecurityException) {
            failPendingConnection("bluetooth_permission", error.message ?: "Bluetooth connection permission is required.")
        } catch (error: Exception) {
            failPendingConnection("connection_failed", error.message ?: "Bluetooth connection failed.")
        }
    }

    private val heartRateGattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                failPendingConnection("connection_failed", "Bluetooth connection failed with code $status.")
                return
            }
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                try {
                    if (!gatt.discoverServices()) {
                        failPendingConnection("service_discovery_failed", "Could not read heart-rate sensor services.")
                    }
                } catch (error: SecurityException) {
                    failPendingConnection("bluetooth_permission", error.message ?: "Bluetooth permission is required.")
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                mainHandler.post {
                    if (activeGatt === gatt) {
                        activeGatt = null
                        eventSink?.success(mapOf("type" to "disconnected"))
                    }
                }
                if (pendingConnectResult != null) {
                    failPendingConnection("connection_failed", "The sensor disconnected before setup finished.")
                }
                try {
                    gatt.close()
                } catch (_: Exception) {
                    // Tidak ada tindakan lanjutan saat GATT sudah ditutup.
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                failPendingConnection("service_discovery_failed", "Could not read heart-rate sensor services.")
                return
            }
            val measurement = gatt.getService(HEART_RATE_SERVICE)
                ?.getCharacteristic(HEART_RATE_MEASUREMENT)
            if (measurement == null) {
                failPendingConnection("heart_rate_unsupported", "This device does not expose the standard Heart Rate service.")
                return
            }
            try {
                if (!gatt.setCharacteristicNotification(measurement, true)) {
                    failPendingConnection("notification_setup_failed", "Could not subscribe to heart-rate updates.")
                    return
                }
                val descriptor = measurement.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG)
                if (descriptor == null) {
                    failPendingConnection("notification_setup_failed", "The heart-rate sensor does not support notifications.")
                    return
                }
                val descriptorStarted = if (Build.VERSION.SDK_INT >= 33) {
                    gatt.writeDescriptor(
                        descriptor,
                        BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
                    ) == BluetoothGatt.GATT_SUCCESS
                } else {
                    enableLegacyNotifications(gatt, descriptor)
                }
                if (!descriptorStarted) {
                    failPendingConnection("notification_setup_failed", "Could not enable heart-rate notifications.")
                    return
                }
            } catch (error: SecurityException) {
                failPendingConnection("bluetooth_permission", error.message ?: "Bluetooth permission is required.")
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            if (descriptor.uuid != CLIENT_CHARACTERISTIC_CONFIG) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                completePendingConnection()
            } else {
                failPendingConnection(
                    "notification_setup_failed",
                    "Android could not enable heart-rate notifications.",
                )
            }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (characteristic.uuid == HEART_RATE_MEASUREMENT) {
                characteristic.value?.let(::emitHeartRateMeasurement)
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            if (characteristic.uuid == HEART_RATE_MEASUREMENT) {
                emitHeartRateMeasurement(value)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun enableLegacyNotifications(
        gatt: BluetoothGatt,
        descriptor: BluetoothGattDescriptor,
    ): Boolean {
        descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        return gatt.writeDescriptor(descriptor)
    }

    private fun emitHeartRateMeasurement(value: ByteArray) {
        if (value.size < 2) return
        val flags = value[0].toInt() and 0xff
        val is16Bit = (flags and 0x01) != 0
        val bpm = if (is16Bit) {
            if (value.size < 3) return
            (value[1].toInt() and 0xff) or ((value[2].toInt() and 0xff) shl 8)
        } else {
            value[1].toInt() and 0xff
        }
        if (bpm !in 25..240) return
        mainHandler.post { eventSink?.success(bpm) }
    }

    private fun completePendingConnection() {
        connectTimeout?.let { mainHandler.removeCallbacks(it) }
        connectTimeout = null
        val result = pendingConnectResult
        pendingConnectResult = null
        result?.success(true)
    }

    private fun failPendingConnection(code: String, message: String) {
        connectTimeout?.let { mainHandler.removeCallbacks(it) }
        connectTimeout = null
        val result = pendingConnectResult
        pendingConnectResult = null
        result?.error(code, message, null)
        val gatt = activeGatt
        activeGatt = null
        try {
            gatt?.disconnect()
            gatt?.close()
        } catch (_: Exception) {
            // GATT mungkin sudah dilepas oleh Android.
        }
    }

    private fun disconnectHeartRateDevice() {
        connectTimeout?.let { mainHandler.removeCallbacks(it) }
        connectTimeout = null
        val result = pendingConnectResult
        pendingConnectResult = null
        result?.error("connection_cancelled", "Bluetooth connection was cancelled.", null)
        val gatt = activeGatt
        activeGatt = null
        try {
            gatt?.disconnect()
            gatt?.close()
        } catch (_: Exception) {
            // GATT mungkin sudah dilepas oleh Android.
        }
    }

    private fun bluetoothAdapter(): BluetoothAdapter? {
        val manager = getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter
    }

    private fun hasBluetoothPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= 31) {
            val scanAllowed = checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
            val connectAllowed = checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
            scanAllowed && connectAllowed
        } else {
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }

    override fun onDestroy() {
        if (scanResult != null) finishHeartRateScan(errorCode = -1, message = "Activity closed during Bluetooth scan.")
        disconnectHeartRateDevice()
        super.onDestroy()
    }
}


/** Membaca sensor langkah bawaan Android tanpa plugin yang menerapkan KGP lama. */
private class StepCounterStreamHandler(
    private val context: Context,
) : EventChannel.StreamHandler, SensorEventListener {
    private var sensorManager: SensorManager? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = manager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (manager == null || sensor == null) {
            events?.error(
                "step_sensor_unavailable",
                "This device does not provide a hardware step counter sensor.",
                null,
            )
            eventSink = null
            return
        }
        sensorManager = manager
        if (!manager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)) {
            events?.error(
                "step_sensor_unavailable",
                "Android could not start the hardware step counter sensor.",
                null,
            )
            sensorManager = null
            eventSink = null
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_STEP_COUNTER) return
        val steps = event.values.firstOrNull()?.toInt() ?: return
        eventSink?.success(
            mapOf(
                "steps" to steps,
                "timestampMillis" to System.currentTimeMillis(),
            ),
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onCancel(arguments: Any?) {
        sensorManager?.unregisterListener(this)
        sensorManager = null
        eventSink = null
    }
}
