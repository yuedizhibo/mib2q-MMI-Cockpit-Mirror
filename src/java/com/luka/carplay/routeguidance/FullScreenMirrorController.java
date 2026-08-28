/*
 * Opt-in full-MMI mirror controller for MHI2Q P1404.
 *
 * The native libcp_mirror hook and the RFB receiver live outside Java.  This
 * controller only owns the cluster-side state that cannot safely be reached
 * from a standalone shell process: a real HMI DisplayManager transition into
 * the firmware-native context 76 (whose first and only source is displayable
 * 58).  It is inert unless both ARMED and RECEIVER_READY
 * exist on the SD card.  Removing ARMED always restores the stock pipeline.
 */
package com.luka.carplay.routeguidance;

import com.luka.carplay.framework.Log;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

public final class FullScreenMirrorController {

    private static final String TAG = "FullScreenMirror";
    private static final String VOL_A = "/net/mmx/fs/sda0";
    private static final String VOL_B = "/net/mmx/fs/sda1";
    private static final String ARM_REL = "/Toolbox/carplay_mirror_test/ARMED";
    private static final String READY_REL = "/Log/CarPlayMirror/receiver_ready";
    private static final String HEARTBEAT_REL = "/Log/CarPlayMirror/worker_heartbeat";
    private static final String STATE_REL = "/Log/CarPlayMirror/java_mirror_state.txt";
    private static final String DIRECT16_REL = "/Toolbox/carplay_mirror_test/DIRECT16_TEST";
    private static final String DIRECT16_STATE_REL =
        "/Log/CarPlayMirror/direct16_test_status.txt";
    private static final String DIRECT16_TIMELINE_REL =
        "/Log/CarPlayMirror/direct16_test_timeline.log";
    private static final String FPS20_REL = "/Toolbox/carplay_mirror_test/FPS20";
    private static final String FPS30_REL = "/Toolbox/carplay_mirror_test/FPS30";
    private static final String FPS40_REL = "/Toolbox/carplay_mirror_test/FPS40";
    private static final String FPS50_REL = "/Toolbox/carplay_mirror_test/FPS50";
    private static final String FPS60_REL = "/Toolbox/carplay_mirror_test/FPS60";
    private static final int POLL_MS = 250;
    private static final int MAX_STAGNANT_POLLS = 80;
    private static final long DIRECT16_DURATION_MS = 15000L;

    private static FullScreenMirrorController singletonOwner;

    private final BAPBridge bap;
    private final Object directCluster;
    private volatile boolean running;
    private volatile boolean requested;
    private volatile boolean active;
    private volatile boolean failedForArm;
    private boolean leftMirrorContext;
    private int suspendedContext;
    private int audiContextPolls;
    private long nextClusterRetryMs;
    private int generation;
    private Thread worker;
    private boolean ownsSingleton;
    private boolean direct16Active;
    private long direct16DeadlineMs;
    private int direct16SavedContext = 74;
    private int direct16RefreshPolls;

    public FullScreenMirrorController(BAPBridge bridge) {
        bap = bridge;
        directCluster = null;
    }

    /**
     * Mirror-only entry used by the CarPlay plugin lifecycle.  It deliberately
     * does not initialize BAP/RGI; the live Navigation singleton is resolved
     * reflectively only when an SD-card test is armed.
     */
    public FullScreenMirrorController() {
        bap = null;
        directCluster = null;
    }

    /** Used by the always-on Navigation ClusterService bootstrap. */
    public FullScreenMirrorController(Object cluster) {
        bap = null;
        directCluster = cluster;
    }

    public synchronized void start() {
        if (running) return;
        synchronized (FullScreenMirrorController.class) {
            if (singletonOwner != null && singletonOwner != this) {
                Log.i(TAG, "Controller already owned by always-on cluster bootstrap");
                ownsSingleton = false;
                return;
            }
            singletonOwner = this;
            ownsSingleton = true;
        }
        running = true;
        requested = false;
        active = false;
        failedForArm = false;
        resetContextReturnTracking();
        nextClusterRetryMs = 0L;
        final int myGeneration = ++generation;
        worker = new Thread(new Runnable() {
            public void run() {
                pollLoop(myGeneration);
            }
        }, "CarPlay-FullMirror");
        worker.setDaemon(true);
        worker.start();
        Log.i(TAG, "Controller started; waiting for SD arm flag");
    }

    public void stop() {
        synchronized (FullScreenMirrorController.class) {
            if (!ownsSingleton || singletonOwner != this) {
                Log.i(TAG, "Ignoring stop from non-owner controller");
                return;
            }
        }
        String armedVolume = findArmedVolume();
        if (armedVolume != null) {
            /* VIEW/layout changes on P1404 can tear down and immediately
             * recreate the route-guidance lifecycle even though the full-MMI
             * mirror test is still running.  Stopping this independent
             * controller here permanently returned the cockpit to the Audi
             * map.  ARMED is owned by the persistent shell watchdog, so keep
             * the controller alive until that watchdog removes the flag. */
            writeState(armedVolume, active ? "ACTIVE" : "WAITING_RECEIVER",
                "Route-guidance lifecycle stop ignored while mirror test is ARMED");
            Log.i(TAG, "Ignoring route-guidance stop while mirror test is ARMED");
            return;
        }
        Thread oldWorker;
        synchronized (this) {
            if (!running && !active) return;
            running = false;
            requested = false;
            failedForArm = false;
            ++generation;
            oldWorker = worker;
            worker = null;
        }
        if (oldWorker != null) oldWorker.interrupt();
        deactivate("CarPlay session stopped");
        synchronized (FullScreenMirrorController.class) {
            if (singletonOwner == this) singletonOwner = null;
            ownsSingleton = false;
        }
        Log.i(TAG, "Controller stopped");
    }

    public boolean isRequested() {
        synchronized (FullScreenMirrorController.class) {
            return singletonOwner != null && singletonOwner.requested;
        }
    }

    private void pollLoop(int myGeneration) {
        boolean loggedWaiting = false;
        String lastHeartbeat = null;
        int heartbeatChanges = 0;
        int stagnantPolls = 0;
        while (running && myGeneration == generation) {
            String directVolume = findDirect16Volume();
            if (directVolume != null || direct16Active) {
                pollDirect16Test(directVolume);
                try {
                    Thread.sleep(POLL_MS);
                } catch (InterruptedException e) {
                    /* Re-check running/generation immediately. */
                }
                continue;
            }

            String volume = findArmedVolume();
            boolean armed = volume != null;
            boolean heartbeatLive = false;

            if (armed) {
                String heartbeat = readSmallFile(volume + HEARTBEAT_REL);
                if (heartbeat != null && !heartbeat.equals(lastHeartbeat)) {
                    if (lastHeartbeat != null) heartbeatChanges++;
                    lastHeartbeat = heartbeat;
                    stagnantPolls = 0;
                } else {
                    stagnantPolls++;
                }
                /* P1404 diagnostics can block the shell worker for several
                 * seconds. Keep the fail-safe, but require 20 seconds of a
                 * completely unchanged heartbeat before restoring context 74. */
                heartbeatLive = heartbeatChanges > 0 && stagnantPolls < MAX_STAGNANT_POLLS;
            }
            requested = armed && heartbeatLive;

            if (!armed) {
                loggedWaiting = false;
                failedForArm = false;
                nextClusterRetryMs = 0L;
                lastHeartbeat = null;
                heartbeatChanges = 0;
                stagnantPolls = 0;
                if (active) deactivate("ARMED removed");
            } else if (active && !heartbeatLive) {
                deactivate("Worker heartbeat stopped");
                failedForArm = true;
                writeState(volume, "FAILED", "Worker heartbeat stopped; stock cluster restored");
            } else if (active && heartbeatLive) {
                monitorClusterReturn(volume);
            } else if (!new File(volume + READY_REL).exists()) {
                if (!loggedWaiting) {
                    writeState(volume, "WAITING_RECEIVER", "Waiting for first decoded MMI frame");
                    Log.i(TAG, "Armed; waiting for receiver first-frame marker");
                    loggedWaiting = true;
                }
            } else if (heartbeatLive && !active && !failedForArm) {
                loggedWaiting = false;
                activate(volume);
            }

            try {
                Thread.sleep(POLL_MS);
            } catch (InterruptedException e) {
                /* Re-check running/generation immediately. */
            }
        }
        if (active) deactivate("Controller thread exited");
        if (direct16Active) finishDirect16Test(null, "Controller thread exited", true);
    }

    /**
     * Fifteen-second, opt-in probe of the firmware's shortest possible path:
     * main HMI displayable 16 -> stock MOST encoder 4 -> cockpit video plane.
     * It never runs together with the persistent source-58 mirror.  The shell
     * launcher temporarily defines context 76 with leading displayable 16;
     * selecting that context makes P1404's native pre-context hook call the
     * private CASI encoder method.  That method is intentionally not exposed
     * by the Java IDisplayManager API, so do not try to reflect it here.
     */
    private synchronized void pollDirect16Test(String volume) {
        if (!direct16Active) {
            if (volume == null) return;
            if (findArmedVolume() != null || active) {
                writeDirect16State(volume, "REFUSED",
                    "Persistent mirror is active; run B1-OFF before this probe", 0, 0);
                new File(volume + DIRECT16_REL).delete();
                return;
            }
            try {
                Object cluster = currentCluster();
                if (cluster == null) throw new IllegalStateException("ClusterService unavailable");
                Object dm = getDisplayManager(cluster);
                int before = getCurrentContext(dm);
                direct16SavedContext = (before == 72 || before == 74) ? before : 74;

                switchContext(dm, 72);
                sleepQuietly(180);
                switchContext(dm, 76);
                sleepQuietly(250);
                invokeOptionalIntInt(dm, "setUpdateRate", 1, 10);

                int after = getCurrentContext(dm);
                if (after != 76) {
                    throw new IllegalStateException(
                        "Context 76 did not activate; currentContext=" + after);
                }
                direct16Active = true;
                direct16DeadlineMs = System.currentTimeMillis() + DIRECT16_DURATION_MS;
                direct16RefreshPolls = 0;
                writeDirect16State(volume, "ACTIVE",
                    "native context hook selected context76 leading source16; context=" + after
                    + " duration_seconds=15 saved_context=" + direct16SavedContext,
                    direct16SavedContext, after);
                appendDirect16Timeline(volume,
                    "ACTIVE route=native-context-hook context=76 leading_source=16"
                    + " saved_context=" + direct16SavedContext);
                Log.i(TAG, "Direct source-16 encoder probe ACTIVE");
            } catch (Throwable t) {
                String detail = t.getClass().getName() + ": " + t.getMessage();
                writeDirect16State(volume, "FAILED", detail, direct16SavedContext, 0);
                appendDirect16Timeline(volume, "FAILED " + detail);
                new File(volume + DIRECT16_REL).delete();
                restoreDirect16BestEffort(direct16SavedContext);
            }
            return;
        }

        if (volume == null) {
            finishDirect16Test(findAnyVolume(), "Test marker removed", false);
            return;
        }
        if (System.currentTimeMillis() >= direct16DeadlineMs) {
            finishDirect16Test(volume, "15-second direct source-16 probe completed", false);
            return;
        }

        /* Re-enter context 76 only if VIEW/layout policy moved elsewhere.  The
         * shell-defined leading displayable makes the native hook reselect 16. */
        direct16RefreshPolls++;
        if (direct16RefreshPolls >= 4) {
            direct16RefreshPolls = 0;
            try {
                Object cluster = currentCluster();
                if (cluster == null) throw new IllegalStateException("ClusterService lost");
                Object dm = getDisplayManager(cluster);
                int context = getCurrentContext(dm);
                if (context != 76) {
                    switchContext(dm, 72);
                    sleepQuietly(100);
                    switchContext(dm, 76);
                    sleepQuietly(120);
                    appendDirect16Timeline(volume,
                        "REENTER context_before=" + context + " context_after="
                        + getCurrentContext(dm) + " leading_source=16");
                }
            } catch (Throwable t) {
                finishDirect16Test(volume,
                    "Refresh failed: " + t.getClass().getName() + ": " + t.getMessage(),
                    true);
            }
        }
    }

    private synchronized void finishDirect16Test(
        String volume, String reason, boolean failed
    ) {
        if (!direct16Active && volume == null) return;
        int saved = direct16SavedContext;
        direct16Active = false;
        direct16DeadlineMs = 0L;
        direct16RefreshPolls = 0;
        restoreDirect16BestEffort(saved);
        if (volume != null) {
            new File(volume + DIRECT16_REL).delete();
            writeDirect16State(volume, failed ? "FAILED" : "FINISHED",
                reason + "; stock encoder/map restored", saved, saved);
            appendDirect16Timeline(volume,
                (failed ? "FAILED " : "FINISHED ") + reason
                + " restored_context=" + saved);
        }
        Log.i(TAG, "Direct source-16 encoder probe ended: " + reason);
    }

    private void restoreDirect16BestEffort(int savedContext) {
        try {
            Object cluster = currentCluster();
            if (cluster == null) return;
            Object dm = getDisplayManager(cluster);
            /* Leave temporary context 76 before the shell watchdog restores
             * its definition from leading source 16 to stable source 58. */
            invokeOptionalIntInt(dm, "setUpdateRate", 1, 0);
            switchContext(dm, 72);
            sleepQuietly(180);
            if (savedContext == 74) {
                switchContext(dm, 74);
                sleepQuietly(180);
            }
        } catch (Throwable t) {
            Log.w(TAG, "direct source-16 restore failed: " + t.getMessage());
        }
    }

    private synchronized void activate(String volume) {
        if (!running || active || failedForArm || !new File(volume + ARM_REL).exists()) return;
        try {
            Object cluster = currentCluster();
            if (cluster == null) {
                /* BAPBridge normally acquires ClusterService lazily when a
                 * CarPlay route-guidance session starts. Full-screen mirroring
                 * deliberately does not require a navigation route, so that
                 * onStart() path may never run. Retry the same lazy initializer
                 * here instead of permanently failing the current arm cycle. */
                long now = System.currentTimeMillis();
                if (now >= nextClusterRetryMs) {
                    nextClusterRetryMs = now + 1000L;
                    try {
                        if (bap == null) throw new IllegalStateException("Using Navigation singleton retry");
                        Method init = bap.getClass().getDeclaredMethod(
                            "initClusterAccess", new Class[0]);
                        init.setAccessible(true);
                        init.invoke(bap, new Object[0]);
                    } catch (Throwable t) {
                        Log.w(TAG, "ClusterService lazy init retry failed: " + t.getMessage());
                    }
                    cluster = currentCluster();
                    if (cluster == null) {
                        writeState(volume, "WAITING_CLUSTER",
                            "ClusterService not ready; retrying without changing cluster state");
                        return;
                    }
                } else {
                    return;
                }
            }

            int fps = requestedFps(volume);
            String result = activateSource58Context(cluster, fps);
            if (result == null || result.startsWith("FAILED")) {
                throw new IllegalStateException(result);
            }

            active = true;
            resetContextReturnTracking();
            writeState(volume, "ACTIVE", result);
            Log.i(TAG, "Mirror ACTIVE: " + result);
        } catch (Throwable t) {
            failedForArm = true;
            active = false;
            String detail = t.getClass().getName() + ": " + t.getMessage();
            writeState(volume, "FAILED", detail);
            Log.e(TAG, "Activation failed: " + detail);
            restoreClusterBestEffort();
        }
    }

    private synchronized void deactivate(String reason) {
        if (!active) return;
        active = false;
        resetContextReturnTracking();
        restoreClusterBestEffort();
        String volume = findAnyVolume();
        if (volume != null) writeState(volume, "IDLE", reason);
        Log.i(TAG, "Mirror deactivated: " + reason);
    }

    private void restoreClusterBestEffort() {
        try {
            Object cluster = currentCluster();
            if (cluster != null) {
                restoreAudiContext(cluster);
            }
        } catch (Throwable t) {
            Log.w(TAG, "cluster restore failed: " + t.getMessage());
        }
    }

    /* VIEW/layout changes on P1404 have now been observed landing directly in
     * either context 72 or 74. Treat two consecutive observations of the same
     * stock context as a settled layout change, then reacquire source 58.
     * During an armed mirror test STOP remains the explicit way to keep stock. */
    private synchronized void monitorClusterReturn(String volume) {
        if (!active) return;
        try {
            Object cluster = currentCluster();
            if (cluster == null) {
                /* RouteGuidance.stop() releases BAP during a VIEW lifecycle
                 * transition.  The controller itself stays alive while
                 * ARMED, so turn this into a recoverable inactive state.  On
                 * the next poll activate() runs BAPBridge's proven lazy
                 * initializer and re-enters context 76. */
                active = false;
                resetContextReturnTracking();
                nextClusterRetryMs = 0L;
                writeState(volume, "SUSPENDED",
                    "ClusterService released by VIEW lifecycle; reinitializing");
                Log.i(TAG, "ClusterService released; scheduling mirror reacquire");
                return;
            }
            Object dm = getDisplayManager(cluster);
            int context = getCurrentContext(dm);
            if (context == 76) {
                if (leftMirrorContext) resetContextReturnTracking();
                return;
            }

            if (!leftMirrorContext) {
                leftMirrorContext = true;
                suspendedContext = context;
                audiContextPolls = (context == 72 || context == 74) ? 1 : 0;
                writeState(volume, "SUSPENDED",
                    "Driver left context 76; currentContext=" + context
                    + "; waiting for stable stock context 72/74");
                return;
            }

            if (context != 72 && context != 74) {
                suspendedContext = context;
                audiContextPolls = 0;
                return;
            }

            if (context == suspendedContext) {
                audiContextPolls++;
            } else {
                suspendedContext = context;
                audiContextPolls = 1;
            }
            if (audiContextPolls >= 2) {
                int fps = requestedFps(volume);
                String result = activateSource58Context(cluster, fps);
                if (result != null && !result.startsWith("FAILED")) {
                    resetContextReturnTracking();
                    writeState(volume, "ACTIVE",
                        "reacquired after VIEW/layout change; " + result);
                    Log.i(TAG, "Mirror reacquired after VIEW/layout change: " + result);
                } else {
                    writeState(volume, "SUSPENDED",
                        "Reacquire attempt failed; " + result);
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "Cluster return monitor failed: " + t.getMessage());
        }
    }

    private void resetContextReturnTracking() {
        leftMirrorContext = false;
        suspendedContext = 0;
        audiContextPolls = 0;
    }

    private static String activateSource58Context(Object cluster, int fps) {
        try {
            Object dm = getDisplayManager(cluster);
            int before = getCurrentContext(dm);

            /* Always make a real transition.  Context 72 is the benign Audi
             * base-map context; context 76 is the P1404-native source-58
             * context discovered from this unit's DisplayManager tables. */
            switchContext(dm, 72);
            sleepQuietly(250);
            switchContext(dm, 76);
            sleepQuietly(250);

            int after = getCurrentContext(dm);
            if (after != 76) {
                switchContext(dm, 72);
                sleepQuietly(200);
                switchContext(dm, 76);
                sleepQuietly(250);
                after = getCurrentContext(dm);
            }
            if (after != 76) {
                return "FAILED: cluster ctx=" + before + "->72->" + after + " not 76";
            }

            invokeOptionalIntInt(dm, "setUpdateRate", 1, fps);
            return "cluster ctx=" + before + "->72->" + after
                + " nativeContext=76 source=58 fps=" + fps;
        } catch (Throwable t) {
            return "FAILED: " + t.getClass().getName() + ": " + t.getMessage();
        }
    }

    private static void restoreAudiContext(Object cluster) throws Exception {
        Object dm = getDisplayManager(cluster);
        invokeOptionalIntInt(dm, "setUpdateRate", 1, 0);
        switchContext(dm, 74);
        sleepQuietly(180);
        if (getCurrentContext(dm) != 74) {
            switchContext(dm, 74);
        }
    }

    private static Object getDisplayManager(Object cluster) throws Exception {
        Object env = getFieldRecursive(cluster, "env");
        Method getHmi = env.getClass().getMethod("getHMIService", new Class[0]);
        Object hmi = getHmi.invoke(env, new Object[0]);
        Method getDm = hmi.getClass().getMethod("getDisplayManager", new Class[0]);
        return getDm.invoke(hmi, new Object[0]);
    }

    private static int getCurrentContext(Object dm) throws Exception {
        Method method = dm.getClass().getMethod(
            "getCurrentContextID", new Class[]{Integer.TYPE});
        Object value = method.invoke(dm, new Object[]{new Integer(1)});
        return ((Integer) value).intValue();
    }

    private static void switchContext(Object dm, int context) throws Exception {
        Method[] methods = dm.getClass().getMethods();
        int i;
        for (i = 0; i < methods.length; i++) {
            Method method = methods[i];
            if ("switchContext".equals(method.getName())
                && method.getParameterTypes().length == 3) {
                method.invoke(dm, new Object[]{new Integer(context), new Integer(1), null});
                return;
            }
        }
        throw new NoSuchMethodException("switchContext(int,int,listener)");
    }

    private static void invokeOptionalIntInt(
        Object owner, String name, int first, int second
    ) {
        try {
            Method method = owner.getClass().getMethod(
                name, new Class[]{Integer.TYPE, Integer.TYPE});
            method.invoke(owner, new Object[]{new Integer(first), new Integer(second)});
        } catch (Throwable t) {
            Log.w(TAG, name + " optional call failed: " + t.getMessage());
        }
    }

    private static void sleepQuietly(long millis) {
        try { Thread.sleep(millis); }
        catch (InterruptedException e) { /* continue recovery/activation */ }
    }

    private static Object getPrivateField(Object owner, String name) throws Exception {
        Field field = owner.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(owner);
    }

    private Object currentCluster() throws Exception {
        if (directCluster != null) return directCluster;
        if (bap != null) return getPrivateField(bap, "csRef");

        /* ClusterService itself lives inside /ifs/lsd.jxe on P1404, so a
         * duplicate class placed in Cockpit_Mirror.jar cannot override its
         * constructor.  Resolve the already-running stock singleton instead.
         * Reflection keeps this class buildable against the small RGI JAR and
         * avoids changing any stock navigation/BAP object. */
        Class navigationClass = Class.forName("de.audi.tghu.navi.app.Navigation");
        Method getInstance = navigationClass.getMethod("getInstance", new Class[0]);
        Object navigation = getInstance.invoke(null, new Object[0]);
        if (navigation == null) return null;
        Method getClusterService = navigation.getClass().getMethod(
            "getClusterService", new Class[0]);
        return getClusterService.invoke(navigation, new Object[0]);
    }

    private static Object getFieldRecursive(Object owner, String name) throws Exception {
        Class type = owner.getClass();
        while (type != null) {
            try {
                Field field = type.getDeclaredField(name);
                field.setAccessible(true);
                return field.get(owner);
            } catch (NoSuchFieldException e) {
                type = type.getSuperclass();
            }
        }
        throw new NoSuchFieldException(name);
    }

    private static String findArmedVolume() {
        if (new File(VOL_A + ARM_REL).exists()) return VOL_A;
        if (new File(VOL_B + ARM_REL).exists()) return VOL_B;
        return null;
    }

    private static String findDirect16Volume() {
        if (new File(VOL_A + DIRECT16_REL).exists()) return VOL_A;
        if (new File(VOL_B + DIRECT16_REL).exists()) return VOL_B;
        return null;
    }

    private static String findAnyVolume() {
        if (new File(VOL_A + "/Toolbox").exists()) return VOL_A;
        if (new File(VOL_B + "/Toolbox").exists()) return VOL_B;
        return null;
    }

    private static int requestedFps(String volume) {
        if (new File(volume + FPS60_REL).exists()) return 60;
        if (new File(volume + FPS50_REL).exists()) return 50;
        if (new File(volume + FPS40_REL).exists()) return 40;
        if (new File(volume + FPS30_REL).exists()) return 30;
        if (new File(volume + FPS20_REL).exists()) return 20;
        return 10;
    }

    private static String readSmallFile(String path) {
        FileInputStream in = null;
        try {
            in = new FileInputStream(path);
            byte[] data = new byte[64];
            int count = in.read(data);
            if (count <= 0) return null;
            return new String(data, 0, count, "UTF-8").trim();
        } catch (Throwable t) {
            return null;
        } finally {
            if (in != null) {
                try { in.close(); } catch (Throwable t) { /* ignore */ }
            }
        }
    }

    private static void writeState(String volume, String state, String detail) {
        FileOutputStream out = null;
        try {
            String text = "state=" + state + "\n"
                + "detail=" + detail + "\n"
                + "controller=full-mmi-mirror-v30-plugin-lifecycle\n";
            out = new FileOutputStream(volume + STATE_REL, false);
            out.write(text.getBytes("UTF-8"));
            out.flush();
        } catch (Throwable t) {
            Log.w(TAG, "State-file write failed: " + t.getMessage());
        } finally {
            if (out != null) {
                try { out.close(); } catch (Throwable t) { /* ignore */ }
            }
        }
    }

    private static void writeDirect16State(
        String volume, String state, String detail, int savedContext, int currentContext
    ) {
        FileOutputStream out = null;
        try {
            String text = "state=" + state + "\n"
                + "detail=" + detail + "\n"
                + "encoder=4\n"
                + "source=16\n"
                + "saved_context=" + savedContext + "\n"
                + "current_context=" + currentContext + "\n"
                + "controller=direct-hmi-displayable16-v1\n";
            out = new FileOutputStream(volume + DIRECT16_STATE_REL, false);
            out.write(text.getBytes("UTF-8"));
            out.flush();
        } catch (Throwable t) {
            Log.w(TAG, "Direct16 state-file write failed: " + t.getMessage());
        } finally {
            if (out != null) {
                try { out.close(); } catch (Throwable t) { /* ignore */ }
            }
        }
    }

    private static void appendDirect16Timeline(String volume, String detail) {
        FileOutputStream out = null;
        try {
            String text = System.currentTimeMillis() + " " + detail + "\n";
            out = new FileOutputStream(volume + DIRECT16_TIMELINE_REL, true);
            out.write(text.getBytes("UTF-8"));
            out.flush();
        } catch (Throwable t) {
            Log.w(TAG, "Direct16 timeline write failed: " + t.getMessage());
        } finally {
            if (out != null) {
                try { out.close(); } catch (Throwable t) { /* ignore */ }
            }
        }
    }
}
