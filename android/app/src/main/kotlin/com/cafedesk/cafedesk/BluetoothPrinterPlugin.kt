package com.cafedesk.cafedesk

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Bluetooth Classic (SPP / RFCOMM) transport for ESC/POS printers.
 *
 * Only transport: it never builds receipts or calculates money. Outcomes are
 * reported honestly to Dart:
 *  - "failed"    nothing was written (Bluetooth off, not paired, cannot connect)
 *  - "unknown"   an error happened after bytes started flowing
 *  - "submitted" every byte was written and flushed to the socket
 * "submitted" does not prove the printer printed (paper out, cover open...).
 */
class BluetoothPrinterPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "cafedesk/bluetooth_printer"
        const val PERMISSION_REQUEST = 4711
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val CHUNK = 512
        private const val PREFS = "cafedesk_bt"
        private const val ASKED = "asked_connect"
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    // One worker: jobs for a printer never interleave.
    private val worker = Executors.newSingleThreadExecutor()
    private val watchdog = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPermission: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        worker.shutdown()
        watchdog.shutdown()
    }

    private val adapter: BluetoothAdapter?
        get() = (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "permissionStatus" -> result.success(permissionStatus())
            "requestPermission" -> requestPermission(result)
            "openAppSettings" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null))
                activity.startActivity(intent)
                result.success(null)
            }
            "bondedDevices" -> bondedDevices(result)
            "send" -> {
                val address = call.argument<String>("address") ?: return result.error("args", "address missing", null)
                val bytes = call.argument<ByteArray>("bytes") ?: return result.error("args", "bytes missing", null)
                val timeout = (call.argument<Int>("timeoutMs") ?: 8000).toLong()
                worker.execute { reply(result, send(address, bytes, timeout)) }
            }
            "test" -> {
                val address = call.argument<String>("address") ?: return result.error("args", "address missing", null)
                val timeout = (call.argument<Int>("timeoutMs") ?: 8000).toLong()
                worker.execute { reply(result, send(address, null, timeout)) }
            }
            else -> result.notImplemented()
        }
    }

    private fun reply(result: MethodChannel.Result, outcome: Map<String, Any?>) = main.post { result.success(outcome) }

    // ---- Permissions -----------------------------------------------------

    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun permissionStatus(): String {
        if (hasConnectPermission()) return "granted"
        val asked = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(ASKED, false)
        // After a denial with "don't ask again", Android stops showing the
        // rationale; the user must allow it in app settings.
        return if (asked && !activity.shouldShowRequestPermissionRationale(Manifest.permission.BLUETOOTH_CONNECT)) {
            "permanently_denied"
        } else {
            "denied"
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasConnectPermission()) return result.success("granted")
        if (pendingPermission != null) return result.error("busy", "A permission request is already open", null)
        pendingPermission = result
        activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(ASKED, true).apply()
        activity.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), PERMISSION_REQUEST)
    }

    fun onPermissionResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val r = pendingPermission ?: return true
        pendingPermission = null
        r.success(permissionStatus())
        return true
    }

    // ---- Devices -------------------------------------------------------------

    private fun bondedDevices(result: MethodChannel.Result) {
        if (!hasConnectPermission()) return result.error("permission", "Bluetooth permission not granted", null)
        val a = adapter ?: return result.success(emptyList<Map<String, Any?>>())
        if (!a.isEnabled) return result.error("bluetooth_off", "Bluetooth is turned off", null)
        try {
            val list = a.bondedDevices.map { d ->
                mapOf("name" to (d.name ?: d.address), "address" to d.address, "class" to (d.bluetoothClass?.majorDeviceClass ?: 0))
            }.sortedBy { it["name"] as String }
            result.success(list)
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        }
    }

    // ---- Sending --------------------------------------------------------------

    private fun failed(msg: String) = mapOf("outcome" to "failed", "error" to msg)
    private fun unknown(msg: String) = mapOf("outcome" to "unknown", "error" to msg)
    private val submitted = mapOf("outcome" to "submitted", "error" to null)

    /** Connects, writes [bytes] (or only connects when null), closes. */
    private fun send(address: String, bytes: ByteArray?, timeoutMs: Long): Map<String, Any?> {
        if (!hasConnectPermission()) return failed("Bluetooth permission is not granted")
        val a = adapter ?: return failed("This device has no Bluetooth")
        if (!a.isEnabled) return failed("Bluetooth is turned off")
        if (!BluetoothAdapter.checkBluetoothAddress(address)) return failed("Invalid Bluetooth address")
        val device: BluetoothDevice = try {
            a.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            return failed("Invalid Bluetooth address")
        }
        try {
            // Discovery slows down connections; needs BLUETOOTH_SCAN on 12+,
            // which this app does not request, so ignore failures here.
            a.cancelDiscovery()
        } catch (_: SecurityException) {
        }

        val socket = connect(device, timeoutMs) ?: return failed("Could not connect to the printer. Is it on, paired and in range?")
        if (bytes == null) {
            closeQuietly(socket)
            return submitted
        }
        var written = 0
        return try {
            val out = socket.outputStream
            while (written < bytes.size) {
                val n = minOf(CHUNK, bytes.size - written)
                out.write(bytes, written, n)
                written += n
            }
            out.flush()
            // Many printers lose the tail of a job if the link drops at once.
            Thread.sleep(minOf(3000L, 400L + bytes.size / 8))
            submitted
        } catch (e: IOException) {
            unknown("Connection lost after $written of ${bytes.size} bytes: ${e.message}")
        } catch (e: InterruptedException) {
            unknown("Interrupted after $written of ${bytes.size} bytes")
        } finally {
            closeQuietly(socket)
        }
    }

    private fun connect(device: BluetoothDevice, timeoutMs: Long): BluetoothSocket? {
        val attempts = listOf<() -> BluetoothSocket>(
            { device.createRfcommSocketToServiceRecord(SPP_UUID) },
            { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) },
        )
        for (create in attempts) {
            var socket: BluetoothSocket? = null
            try {
                socket = create()
                val s = socket
                // connect() has no timeout of its own: close it from a watchdog.
                val guard = watchdog.schedule({ closeQuietly(s) }, timeoutMs, TimeUnit.MILLISECONDS)
                s.connect()
                guard.cancel(false)
                return s
            } catch (e: IOException) {
                closeQuietly(socket)
            } catch (e: SecurityException) {
                closeQuietly(socket)
                return null
            }
        }
        return null
    }

    private fun closeQuietly(socket: BluetoothSocket?) {
        try {
            socket?.close()
        } catch (_: IOException) {
        }
    }
}
