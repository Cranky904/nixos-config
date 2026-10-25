{ pkgs, ... }:
let
  visibilityQml = pkgs.writeText "ClockVisibility.qml" ''
    import QtQuick

    QtObject {
        id: state

        property bool idle: false
        property bool fullscreen: false
        property bool workspaceReveal: false
        property bool cornerReveal: false
        property bool inputPending: false
        property bool cursorKnown: false
        property point lastCursor: Qt.point(0, 0)
        readonly property bool compact: !fullscreen
            && (idle || workspaceReveal || cornerReveal)

        // Let the workspace shortcut finish before ordinary input hides its reveal.
        property Timer workspaceGrace: Timer { interval: 150 }

        function activity() {
            if (!workspaceGrace.running)
                workspaceReveal = false;
            inputPending = true;
        }

        function workspaceChanged() {
            workspaceReveal = true;
            workspaceGrace.restart();
        }

        function cursorSample(x, y, monitorX, monitorY) {
            const moved = !cursorKnown || x !== lastCursor.x || y !== lastCursor.y;
            const inCorner = x >= monitorX && x < monitorX + 8
                && y >= monitorY && y < monitorY + 8;

            // Entering the corner overrides pointer activity. Typing or clicking
            // with a stationary pointer still dismisses the clock.
            cornerReveal = !fullscreen && inCorner
                && (moved || (cornerReveal && !inputPending));
            if (moved && cursorKnown && !workspaceGrace.running)
                workspaceReveal = false;
            lastCursor = Qt.point(x, y);
            cursorKnown = true;
            inputPending = false;
        }

        onFullscreenChanged: {
            workspaceReveal = false;
            cornerReveal = false;
            workspaceGrace.stop();
        }
    }
  '';

  shellQml = pkgs.writeText "shell.qml" ''
    import Quickshell
    import Quickshell.Hyprland
    import Quickshell.Io
    import Quickshell.Wayland
    import QtQuick

    ShellRoot {
        id: root

        readonly property var mainMonitor: Hyprland.monitors.values.find(
            monitor => monitor.name === "HDMI-A-1") ?? null

        ClockVisibility {
            id: visibilityState
            idle: idleMonitor.isIdle
            // Visible fullscreen workspaces on either monitor suppress the clock.
            fullscreen: Hyprland.workspaces.values.some(
                workspace => workspace.active && workspace.hasFullscreen)
        }

        IdleMonitor {
            id: idleMonitor
            timeout: 5
            respectInhibitors: false
        }

        // A short, nonzero timeout rearms between input events, including keys
        // while a workspace/corner reveal is visible. No key contents are read.
        IdleMonitor {
            timeout: 0.001
            respectInhibitors: false
            onIsIdleChanged: if (!isIdle) visibilityState.activity()
        }

        Connections {
            target: Hyprland
            function onRawEvent(event) {
                if (event.name === "workspacev2")
                    Qt.callLater(() => visibilityState.workspaceChanged());
            }
        }

        // Read cursor position without an invisible window stealing corner input
        // or spawning hyprctl processes on every poll.
        Socket {
            id: cursorSocket
            property string response: ""
            path: Hyprland.requestSocketPath
            onConnectionStateChanged: {
                if (connected) {
                    response = "";
                    write("j/cursorpos");
                    flush();
                    cursorTimeout.restart();
                } else {
                    cursorTimeout.stop();
                }
            }
            onError: visibilityState.cornerReveal = false
            parser: SplitParser {
                splitMarker: ""
                onRead: data => {
                    cursorSocket.response += data;
                    let position;
                    try {
                        position = JSON.parse(cursorSocket.response);
                    } catch (error) {
                        return; // A JSON response may arrive in several chunks.
                    }
                    cursorSocket.connected = false;
                    if (root.mainMonitor && Number.isFinite(position.x)
                        && Number.isFinite(position.y)) {
                        visibilityState.cursorSample(position.x, position.y,
                            root.mainMonitor.x, root.mainMonitor.y);
                    }
                }
            }
        }

        Timer {
            id: cursorTimeout
            interval: 250
            onTriggered: {
                cursorSocket.connected = false;
                visibilityState.cornerReveal = false;
            }
        }

        Timer {
            interval: 100
            repeat: true
            running: root.mainMonitor !== null
            triggeredOnStart: true
            onTriggered: if (!cursorSocket.connected) cursorSocket.connected = true
        }

        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        Variants {
            model: Quickshell.screens.filter(screen => screen.name === "HDMI-A-1")

            PanelWindow {
                required property var modelData
                screen: modelData
                visible: visibilityState.compact

                anchors { top: true; left: true }
                margins { top: 8; left: 8 }
                implicitWidth: Math.ceil(timeText.implicitWidth) + 20
                implicitHeight: Math.ceil(timeText.implicitHeight) + 12
                color: "transparent"

                // Float over ordinary windows without reserving space.
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-clock"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}

                // Native compositor blur follows the rounded glass surface.
                BackgroundEffect.blurRegion: Region {
                    item: background
                    radius: background.radius
                }

                Rectangle {
                    id: background
                    anchors.fill: parent
                    radius: height / 2
                    color: "#bf151515"
                    antialiasing: true

                    Text {
                        id: timeText
                        anchors.centerIn: parent
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: "#ffffff"
                        font.family: "0xProto Nerd Font Mono"
                        font.pixelSize: 12
                        font.weight: Font.Normal
                    }
                }
            }
        }
    }
  '';
in {
  home.packages = [ pkgs.quickshell ];

  xdg.configFile."quickshell/shell.qml".source = shellQml;
  xdg.configFile."quickshell/ClockVisibility.qml".source = visibilityQml;

  # Compositor fades include the glass blur. Unmapping leaves no hidden surface
  # or residual frosted patch; disabling compositor animations is respected.
  wayland.windowManager.hyprland.settings.layerrule = [
    "animation fade, match:namespace ^(quickshell-clock)$"
  ];

  systemd.user.services.quickshell = {
    Unit = {
      Description = "Quickshell compact clock";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.quickshell}/bin/quickshell";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
