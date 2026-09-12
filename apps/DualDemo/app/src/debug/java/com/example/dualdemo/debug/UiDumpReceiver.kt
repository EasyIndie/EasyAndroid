package com.example.dualdemo.debug

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * 让应用**自己**截自己的屏,再落成 PNG 供 `adb pull` 取走。
 *
 * 为什么需要它
 *   Pico 4 给每个应用建独立虚拟 display 且全部带 `FLAG_SECURE`,
 *   `adb exec-out screencap` 只能得到一张纯白图,`scrcpy` 同理(见 docs/04)。
 *   但 `FLAG_SECURE` 只阻止**别的进程**去抓屏 —— 应用把**自己的** View 层级
 *   画到一张 Bitmap 上是完全允许的,因为那本来就是它自己的 surface。
 *
 * 触发方式
 *   adb shell am broadcast -a <applicationId>.DUMP_UI -p <applicationId>
 *
 * 产物
 *   /sdcard/Android/data/<applicationId>/files/ui-dump.png
 *
 * 已知限制
 *   · SurfaceView / TextureView / VideoView 这类**独立 surface** 的内容画不进来
 *     (它们不走 View.draw 的软件绘制路径),截出来会是黑的
 *   · 应用必须在**前台**。后台时 View 已经不再重绘,抓到的是过期的画面
 */
class UiDumpReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val activity = DebugHooks.current
        if (activity == null) {
            Log.w(TAG, "没有处于 resumed 状态的 Activity —— 应用在前台吗?")
            return
        }
        val appContext = context.applicationContext
        // onReceive 本身就在主线程,post 一次是为了让当前这一帧先画完
        Handler(Looper.getMainLooper()).post { capture(activity, appContext) }
    }

    private fun capture(activity: android.app.Activity, context: Context) {
        val out = File(context.getExternalFilesDir(null) ?: context.filesDir, FILE_NAME)
        try {
            val root = activity.window.decorView
            if (root.width <= 0 || root.height <= 0) {
                Log.w(TAG, "View 还没完成布局,跳过")
                return
            }
            val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
            // 软件绘制:不受 FLAG_SECURE 影响,因为这是我们自己的画布
            root.draw(Canvas(bitmap))
            out.parentFile?.mkdirs()
            FileOutputStream(out).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
            Log.i(TAG, "已写出 ${out.absolutePath} (${root.width}x${root.height})")
        } catch (t: Throwable) {
            Log.e(TAG, "截图失败", t)
        }
    }

    companion object {
        const val TAG = "UiDump"
        const val FILE_NAME = "ui-dump.png"

        /** 广播 action 后缀,完整 action = "<applicationId>.DUMP_UI" */
        const val ACTION_SUFFIX = ".DUMP_UI"
    }
}
