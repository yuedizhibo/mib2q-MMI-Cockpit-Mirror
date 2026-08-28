package com.luka.carplay.routeguidance;

import java.io.File;
import java.io.FileOutputStream;

/**
 * Safe, idempotent entry point called after the stock Navigation
 * ClusterService constructor completes. ClusterService belongs to the
 * always-on navigation application, so this does not depend on TerminalMode,
 * an attached phone, or an active CarPlay session.
 *
 * The controller itself remains inert until the Toolbox worker creates both
 * ARMED and receiver_ready on the SD card. Never let an optional diagnostic
 * failure escape into the stock ClusterService constructor.
 */
public final class StandaloneMirrorBootstrap {
    private static FullScreenMirrorController controller;

    private StandaloneMirrorBootstrap() {
    }

    public static synchronized void attach(Object clusterService) {
        if (clusterService == null || controller != null) return;
        try {
            FullScreenMirrorController candidate =
                new FullScreenMirrorController(clusterService);
            candidate.start();
            controller = candidate;
            writeBootstrapState("ATTACHED", clusterService.getClass().getName());
        } catch (Throwable failure) {
            controller = null;
            writeBootstrapState("FAILED",
                failure.getClass().getName() + ": " + failure.getMessage());
        }
    }

    private static void writeBootstrapState(String state, String detail) {
        String volume = null;
        if (new File("/net/mmx/fs/sda0/Toolbox").exists()) volume = "/net/mmx/fs/sda0";
        else if (new File("/net/mmx/fs/sda1/Toolbox").exists()) volume = "/net/mmx/fs/sda1";
        if (volume == null) return;
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(
                volume + "/Log/CarPlayMirror/bootstrap_state.txt", false);
            String text = "state=" + state + "\n"
                + "detail=" + detail + "\n"
                + "controller=full-mmi-mirror-v27-mirror-only\n";
            out.write(text.getBytes("UTF-8"));
            out.flush();
        } catch (Throwable ignored) {
            /* Diagnostics must never affect the stock navigation service. */
        } finally {
            if (out != null) {
                try { out.close(); } catch (Throwable ignored) { }
            }
        }
    }
}
