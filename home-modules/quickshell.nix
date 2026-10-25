{ pkgs, ... }:
let
  shellQml = pkgs.writeText "shell.qml" ''
    import Quickshell
    import Quickshell.Wayland
    import QtQuick

    ShellRoot {
        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        Variants {
            model: Quickshell.screens.filter(screen => screen.name === "HDMI-A-1")

            PanelWindow {
                required property var modelData
                screen: modelData

                anchors { top: true; right: true }
                margins { top: 8; right: 8 }
                implicitWidth: Math.ceil(timeText.implicitWidth) + 20
                implicitHeight: Math.ceil(timeText.implicitHeight) + 12
                color: "transparent"

                // Float over windows, including fullscreen, without reserving space.
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
