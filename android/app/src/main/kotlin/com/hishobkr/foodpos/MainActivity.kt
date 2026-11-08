package com.hishobkr.foodpos

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hishobkr/usb_printer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "list" -> result.success(listPrinters())
                    "print" -> {
                        val vendorId = call.argument<Int>("vendorId")
                        val productId = call.argument<Int>("productId")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (vendorId == null || productId == null || bytes == null) {
                            result.error("bad_args", "Missing printer id or data", null)
                        } else {
                            printTo(vendorId, productId, bytes, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private val usbManager: UsbManager
        get() = getSystemService(Context.USB_SERVICE) as UsbManager

    /** A printer is any USB device with a bulk-OUT endpoint, preferring the printer class. */
    private fun bulkOut(device: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        var fallback: Pair<UsbInterface, UsbEndpoint>? = null
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            for (e in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    ep.direction == UsbConstants.USB_DIR_OUT
                ) {
                    if (intf.interfaceClass == UsbConstants.USB_CLASS_PRINTER) return intf to ep
                    if (fallback == null) fallback = intf to ep
                }
            }
        }
        return fallback
    }

    private fun listPrinters(): List<Map<String, Any>> =
        usbManager.deviceList.values.filter { bulkOut(it) != null }.map {
            mapOf(
                "vendorId" to it.vendorId,
                "productId" to it.productId,
                "name" to (it.productName ?: it.manufacturerName ?: "USB printer"),
            )
        }

    private fun printTo(vendorId: Int, productId: Int, bytes: ByteArray, result: MethodChannel.Result) {
        val device = usbManager.deviceList.values.firstOrNull {
            it.vendorId == vendorId && it.productId == productId
        }
        if (device == null) {
            result.error("not_found", "Printer not connected. Check the USB cable.", null)
            return
        }
        if (usbManager.hasPermission(device)) {
            send(device, bytes, result)
            return
        }
        requestPermission(device) { granted ->
            if (granted) send(device, bytes, result)
            else result.error("denied", "USB permission was not granted.", null)
        }
    }

    private fun requestPermission(device: UsbDevice, done: (Boolean) -> Unit) {
        val action = "$packageName.USB_PRINTER_PERMISSION"
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != action) return
                unregisterReceiver(this)
                done(intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false))
            }
        }
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        // The USB service fills in EXTRA_PERMISSION_GRANTED, so the intent must
        // be mutable; Android 14 then requires it to be explicit.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val intent = Intent(action).setPackage(packageName)
        usbManager.requestPermission(device, PendingIntent.getBroadcast(this, 0, intent, flags))
    }

    private fun send(device: UsbDevice, bytes: ByteArray, result: MethodChannel.Result) {
        thread {
            val target = bulkOut(device)
            val conn = usbManager.openDevice(device)
            if (target == null || conn == null) {
                runOnUiThread { result.error("open_failed", "Could not open the USB printer.", null) }
                return@thread
            }
            val (intf, ep) = target
            try {
                if (!conn.claimInterface(intf, true)) {
                    runOnUiThread { result.error("busy", "USB printer is busy.", null) }
                    return@thread
                }
                var offset = 0
                while (offset < bytes.size) {
                    val len = minOf(16384, bytes.size - offset)
                    val sent = conn.bulkTransfer(ep, bytes, offset, len, 5000)
                    if (sent <= 0) {
                        runOnUiThread { result.error("write_failed", "USB printer stopped responding.", null) }
                        return@thread
                    }
                    offset += sent
                }
                runOnUiThread { result.success(true) }
            } finally {
                conn.releaseInterface(intf)
                conn.close()
            }
        }
    }
}
