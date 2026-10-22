{ pkgs, ... }:
let
  cWhite     = "#ebdbb2";
  cGray      = "#343434";
  cGrayerGray = "#262626";
  cDarkGray  = "#151515";
  barWidth   = 44;
  cornerSize = 16;

  shellQml = pkgs.writeText "shell.qml" ''
    import Quickshell
    import Quickshell.Io
    import QtQuick
    import QtQuick.Layouts
    import QtQuick.Controls
    import Quickshell.Hyprland
    import Quickshell.Services.Pipewire
    import Quickshell.Services.Mpris
    import Quickshell.Services.SystemTray

    Scope {
        id: root

        property color cWhite: "${cWhite}"
        property color cGray: "${cGray}"
        property color cGrayerGray: "${cGrayerGray}"
        property color cDarkGray: "${cDarkGray}"
        property int barWidth: ${toString barWidth}
        property int cornerSize: ${toString cornerSize}
        property string fontFamily: "0xProto Nerd Font Mono"
        property int fontSize: 13

        // cpu state
        property int cpuPct: 0
        property int memPct: 0
        property int _lastCpuIdle: 0
        property int _lastCpuTotal: 0
        property bool calVisible: false
        property date calDate: new Date()
        property bool wsVisible: false
        property var focusedWs: Hyprland.focusedWorkspace
        property var wsIcons: ({
            1: "",
            2: "",
            3: "󰆍",
            4: "",
            5: "",
            6: "",
            7: "",
            8: "",
            9: "",
            10: "",
            21: "",
            22: "",
            23: "",
            24: "",
        })
        property bool statsVisible: false
        property color barCpuColor: "#FAE311"
        property color barMemColor: "#0ECF08"
        property int cpuTemp: 0
        property var corePcts: []
        property var _lastCores: []
        property int memUsedMb: 0
        property int memTotalMb: 0
        property bool mediaVisible: false
        property bool sinksExpanded: false
        property int volume: 0
        property bool muted: false
        property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
        property bool trayVisible: false
        property string weatherCity: "Budapest"
        property string weatherTemp: ""
        property string weatherDesc: ""
        property bool launcherVisible: false
        property bool barVisible: true
        property var hiddenWsIds: [21, 22, 23]
        property var visibleWorkspaces: {
          var out = []
          var values = Hyprland.workspaces.values
          for (var i = 0; i < values.length; i++) {
            var ws = values[i]
            if (hiddenWsIds.indexOf(ws.id) === -1 && ws.id > 0)
              out.push(ws)
          }
          return out
        }
        property bool hiddenWsFocused: root.focusedWs !== null
          && hiddenWsIds.indexOf(root.focusedWs.id) !== -1

        function makeBar(pct, color, width) {
          var filled = Math.round(pct / 100 * width)
          var s = ""
          for (var i = 0; i < width; i++)
            s += "|"
          return { filled: s.substring(0, filled), empty: s.substring(filled) }
        }

        function wsIcon(id) {
          return wsIcons[id] !== undefined ? wsIcons[id] : ""
        }

        onFocusedWsChanged: {
          if (wsPopup.hovered) return
          wsVisible = true
          wsHideTimer.restart()
        }

        Timer {
          id: wsHideTimer
          interval: 1500
          onTriggered: if (!wsPopup.hovered) root.wsVisible = false
        }

        // clock (auto-updating)
        SystemClock {
            id: myClock
        }

        PwObjectTracker {
          objects: Pipewire.nodes
        }

IpcHandler {
    target: "launcher"

    function toggle(): void {
        root.launcherVisible = !root.launcherVisible
    }

    function toggleBar(): void {
        root.barVisible = !root.barVisible
    }
}
        Process {
    id: weatherProc
    command: ["sh", "-c", "curl -s 'wttr.in/" + root.weatherCity + "?format=%t|%C'"]
    running: true
    stdout: SplitParser {
        onRead: data => {
            var p = data.trim().split("|")
            if (p.length >= 2) {
                root.weatherTemp = p[0]
                root.weatherDesc = p[1]
            }
        }
    }
}
Timer {
    interval: 1800000
    running: true
    repeat: true
    onTriggered: weatherProc.running = true
}

Process {
    id: volProc
    command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
    running: true
    stdout: SplitParser {
        onRead: data => {
            var p = data.trim().split(/\s+/)
            root.volume = Math.round(parseFloat(p[1]) * 100)
            root.muted = data.indexOf("MUTED") !== -1
        }
    }
}

Process {
    id: tempProc
        command: ["sh", "-c", "for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type); case $t in k10temp|x86_pkg_temp|coretemp) cat $z/temp; break;; esac; done"]

    running: true
    stdout: SplitParser {
        onRead: data => {
            var t = parseInt(data.trim())
            if (t > 1000) t = Math.round(t / 1000)
            if (t > 0) root.cpuTemp = t
        }
    }
}
Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: tempProc.running = true
}
Process {
    id: cpuProc
    command: ["sh", "-c", "head -1 /proc/stat"]
    running: true
    stdout: StdioCollector {
        onStreamFinished: {
            var p = this.text.trim().split(/\s+/).filter(function(s) { return s !== "" })
            var idle = parseInt(p[4]) + parseInt(p[5])
            var total = 0
            for (var i = 1; i <= 8 && p[i]; i++)
                total += parseInt(p[i])
            var dI = idle - root._lastCpuIdle
            var dT = total - root._lastCpuTotal
            if (root._lastCpuTotal > 0 && dT > 0)
                root.cpuPct = Math.round((1 - dI / dT) * 100)
            root._lastCpuIdle = idle
            root._lastCpuTotal = total
        }
    }
}
Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: cpuProc.running = true
}
        Process {
          id: memProc
          command: ["sh", "-c", "free -m | awk '/Mem:/ {print int($3*100/$2), $3, $2}'"]
          running: true
          stdout: SplitParser {
            onRead: data => {
              var p = data.trim().split(/\s+/)
              if (p.length >= 3) {
                root.memPct = parseInt(p[0]) || 0
                root.memUsedMb = parseInt(p[1]) || 0
                root.memTotalMb = parseInt(p[2]) || 0
              
            
              }
            }
          }
        }
        Timer {
          interval: 1000
          running: true
          repeat: true
          onTriggered: memProc.running = true
        }

        PopupWindow {
    id: statsPopup
    visible: root.statsVisible

    anchor.window: bar
    anchor.rect.x: root.barWidth + 5
    anchor.rect.y: 50
    anchor.rect.width: 1
    anchor.rect.height: 1

    implicitWidth: statsCol.implicitWidth + 24
    implicitHeight: statsCol.implicitHeight + 24
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        x: root.statsVisible ? 0 : -width - 20
        opacity: root.statsVisible ? 1 : 0
        color: root.cDarkGray
        radius: root.cornerSize
        border.color: root.cGray
        border.width: 1

        Behavior on x {
          NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: 250 }
        }

        Column {
            id: statsCol
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: "CPU      " + root.cpuTemp + "°C"
                color: root.cWhite
                font.family: root.fontFamily
                font.pixelSize: root.fontSize
            }
            Row {
                spacing: 0
                property var b: root.makeBar(root.cpuPct, root.barCpuColor, 24)
                Text {
                    text: parent.b.filled
                    color: root.barCpuColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 2
                }
                Text {
                    text: parent.b.empty
                    color: root.cGray
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 2
                }
            }
            Rectangle { width: 1; height: 4; color: "transparent" }

            Text {
                text: "RAM " + root.memUsedMb + " / " + root.memTotalMb + " MB"
                color: root.cWhite
                font.family: root.fontFamily
                font.pixelSize: root.fontSize
            }
            Row {
                spacing: 0
                property var b: root.makeBar(root.memPct, root.barMemColor, 24)
                Text {
                    text: parent.b.filled
                    color: root.barMemColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 2
                }
                Text {
                    text: parent.b.empty
                    color: root.cGray
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 2
                }
            }
        }
    }
}

PopupWindow {
    id: mediaPopup
    visible: root.mediaVisible

    anchor.window: bar
    anchor.rect.x: root.barWidth + 5
    anchor.rect.y: 140
    anchor.rect.width: 1
    anchor.rect.height: 1

    implicitWidth: 300
    implicitHeight: mediaCol.implicitHeight + 24
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        x: root.mediaVisible ? 0 : -width - 20
        opacity: root.mediaVisible ? 1 : 0
        color: root.cDarkGray
        radius: root.cornerSize
        border.color: root.cGray
        border.width: 1

        Behavior on x {
          NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: 250 }
        }

        Column {
            id: mediaCol
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 12
            width: parent.width - 24
            spacing: 10

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.player ? (root.player.trackTitle || "unknown") + " - " + (root.player.trackArtist || "") : "nothing playing"
                color: root.cWhite
                font.family: root.fontFamily
                font.pixelSize: root.fontSize
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20

                Text {
                    text: "󰒮"
                    color: root.cWhite
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize + 8
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.player) root.player.previous()
                    }
                }
                Text {
                    text: root.player && root.player.playbackState === MprisPlaybackState.Playing ? "󰏤" : "󰐊"
                    color: root.cWhite
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize + 8
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.player) root.player.togglePlaying()
                    }
                }
                Text {
                    text: "󰒭"
                    color: root.cWhite
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize + 8
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.player) root.player.next()
                    }
                }
            }

            // master volume slider
            Row {
                width: parent.width
                spacing: 8

                Item {
                    width: parent.width - 28
                    height: 20

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: root.cGray

                        Rectangle {
                            width: parent.width * Math.min(root.volume, 100) / 100
                            height: parent.height
                            radius: 2
                            color: root.cWhite
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            var v = Math.round(mouse.x / width * 100)
                            Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v + "%"])
                            volProc.running = true
                        }
                    }
                }

                Text {
                    text: root.sinksExpanded ? "󰅃" : "󰅀"
                    color: root.cWhite
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize + 2
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sinksExpanded = !root.sinksExpanded
                    }
                }
            }

            // per-app volumes
            Repeater {
    model: root.sinksExpanded ? Pipewire.nodes.values.filter(n => n.isStream && n.audio) : []

                delegate: Column {
        required property var modelData
        width: mediaCol.width
        spacing: 2

        PwObjectTracker { objects: [modelData] }

        Row {
            spacing: 6
            width: parent.width

            Image {
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                source: Quickshell.iconPath(modelData.properties["application.icon-name"] || "audio-x-generic", true)
            }

            Text {
                width: parent.width - 22
                text: modelData.properties["application.name"] || modelData.description || modelData.name
                color: root.cWhite
                font.family: root.fontFamily
                font.pixelSize: root.fontSize - 2
                elide: Text.ElideRight
            }
        }

        Item {
            width: parent.width
            height: 16

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: root.cGray

                Rectangle {
                    width: parent.width * Math.min(modelData.audio.volume, 1.0)
                    height: parent.height
                    radius: 2
                    color: "#b8bb26"
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    modelData.audio.volume = Math.min(mouse.x / width, 1.0)
                }
            }
        }
    }
}
}
}
}

PopupWindow {
    id: trayPopup
    visible: root.trayVisible

    anchor.window: bar
    anchor.rect.x: root.barWidth + 5
    anchor.rect.y: bar.height - 80
    anchor.rect.width: 1
    anchor.rect.height: 1

    implicitWidth: trayGrid.implicitWidth + 20
    implicitHeight: trayGrid.implicitHeight + 20
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        x: root.trayVisible ? 0 : -width - 20
        opacity: root.trayVisible ? 1 : 0
        color: root.cDarkGray
        radius: root.cornerSize
        border.color: root.cGray
        border.width: 1

        Behavior on x {
          NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: 250 }
        }

        Grid {
            id: trayGrid
            anchors.centerIn: parent
            columns: 2
            spacing: 10

            Repeater {
                model: SystemTray.items

                delegate: Item {
                    required property var modelData
                    width: 32
                    height: 32

                    Image {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        source: Quickshell.iconPath(modelData.icon, true)
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                modelData.activate()
                                root.trayVisible = false
                            } else if (mouse.button === Qt.MiddleButton) {
                                Quickshell.execDetached(["sh", "-c", "pkill -f '" + modelData.id + "'"])
                            } else if (mouse.button === Qt.RightButton) {
                                modelData.display(bar, 0, 0)
                            }
                        }
                    }
                }
            }
        }
    }
}

PopupWindow {
    id: launcherPopup
    visible: root.launcherVisible

    anchor.window: bar
    anchor.rect.x: root.barWidth + 5
    anchor.rect.y: bar.height / 2 - 320
    anchor.rect.width: 1
    anchor.rect.height: 1

    implicitWidth: launcherCol.implicitWidth + 20
    implicitHeight: launcherCol.implicitHeight + 20
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        x: root.launcherVisible ? 0 : -width - 20
        opacity: root.launcherVisible ? 1 : 0
        color: root.cDarkGray
        radius: root.cornerSize
        border.color: root.cGray
        border.width: 1

        Behavior on x {
          NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: 250 }
        }

        Column {
            id: launcherCol
            anchors.centerIn: parent
            spacing: 12

            Repeater {
                model: [
                    { icon: "󰮫", cmd: ["vicinae", "toggle"], close: true },
                    { icon: "󱚾", cmd: ["kitty", "-e", "nmtui"], close: true },
                    { icon: "󰜉", cmd: ["systemctl", "reboot"], close: false },
                    { icon: "󰐥", cmd: ["systemctl", "poweroff"], close: false },
                    { icon: "󰖰", cmd: ["qs", "ipc", "call", "launcher", "toggleBar"], close: true }
                ]

                delegate: Rectangle {
                    required property var modelData
                    width: 44
                    height: 44
                    radius: 10
                    color: btnMa.containsMouse ? root.cGrayerGray : "transparent"
                    border.color: root.cGray
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: modelData.icon
                        color: root.cWhite
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize + 8
                    }

                    MouseArea {
                        id: btnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(modelData.cmd)
                            if (modelData.close) root.launcherVisible = false
                        }
                    }
                }
            }
        }
    }
}

PopupWindow {
            id: wsPopup
            visible: root.wsVisible

            property bool hovered: hoverMa.containsMouse

            anchor.window: bar
            anchor.rect.x: root.barWidth + 5
            anchor.rect.y: bar.height - 37
            anchor.rect.width: 1
            anchor.rect.height: 1

            implicitWidth: Math.max(wsRow.implicitWidth, hiddenWsRow.implicitWidth) + 10
            implicitHeight: root.hiddenWsFocused ? 82 : 38
            color: "transparent"

            Column {
                anchors.fill: parent
                spacing: 6

                // hidden discord workspaces, only visible while on one
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: hiddenWsRow.implicitWidth + 10
                    height: root.hiddenWsFocused ? 38 : 0
                    opacity: root.hiddenWsFocused ? 1 : 0
                    color: root.cDarkGray
                    radius: root.cornerSize
                    border.color: root.cGray
                    border.width: 1
                    clip: true

                    Behavior on height {
                        NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }

                    Row {
                        id: hiddenWsRow
                        anchors.centerIn: parent
                        spacing: 8

                        Repeater {
                            model: root.hiddenWsIds

                            delegate: Rectangle {
                                id: hiddenDelegate
                                required property var modelData
                                required property int index
                                property bool active: root.focusedWs !== null
                                    && root.focusedWs.id === modelData

                                width: 30
                                height: 30
                                radius: 10
                                color: active ? root.cWhite : "transparent"
                                border.color: root.cGray
                                border.width: 1
                                scale: active ? 1.15 : 1.0

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 3
                                    }
                                }
                                Behavior on color {
                                    ColorAnimation { duration: 200 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.wsIcon(hiddenDelegate.modelData)
                                    color: hiddenDelegate.active ? root.cDarkGray : root.cWhite
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 10
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Hyprland.dispatch("workspace " + hiddenDelegate.modelData)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 38
                    x: root.wsVisible ? 0 : -width - 20
                    opacity: root.wsVisible ? 1 : 0
                    color: root.cDarkGray
                    radius: root.cornerSize
                    border.color: root.cGray
                    border.width: 1

                    Behavior on x {
                        NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 250 }
                    }

                    MouseArea {
                        id: hoverMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onExited: wsHideTimer.restart()
                    }

                    Row {
                        id: wsRow
                        anchors.centerIn: parent
                        spacing: 8

                        Repeater {
                            model: root.visibleWorkspaces

                            delegate: Rectangle {
                                id: wsDelegate
                                required property var modelData
                                required property int index
                                property bool active: modelData === root.focusedWs

                                width: 30
                                height: 30
                                radius: 10
                                color: active ? root.cWhite : "transparent"
                                border.color: root.cGray
                                border.width: 1
                                opacity: root.wsVisible ? 1 : 0
                                scale: root.wsVisible ? (active ? 1.15 : 1.0) : 0.3

                                Behavior on opacity {
                                    SequentialAnimation {
                                        PauseAnimation { duration: wsDelegate.index * 40 }
                                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                    }
                                }
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 3
                                    }
                                }
                                Behavior on color {
                                    ColorAnimation { duration: 200 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.wsIcon(modelData.id)
                                    color: wsDelegate.active ? root.cDarkGray : root.cWhite
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 10
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Hyprland.dispatch("workspace " + modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        PanelWindow {
    id: bar
    anchors.left: true
    anchors.top: true
    anchors.bottom: true
    margins.left: root.barVisible ? 4 : -(root.barWidth + 12)
    margins.top: 4
    margins.bottom: 4
    exclusiveZone: root.barVisible ? root.barWidth + 4 : 0
    implicitWidth: root.barWidth
    color: "transparent"

    Behavior on margins.left {
        NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
    }

            PopupWindow {
              id: calPopup
              visible: root.calVisible

              anchor.window: bar
              anchor.rect.x: root.barWidth + 5
              anchor.rect.y: 4
              anchor.rect.width: 1
              anchor.rect.height: 1
              implicitWidth: 260
              implicitHeight: 300
              color: "transparent"

            Rectangle {
              anchors.fill: parent
              x: root.calVisible ? 0 : -width - 20
              opacity: root.calVisible ? 1 : 0
              color: root.cDarkGray
              radius: root.cornerSize
              border.color: root.cGray
              border.width: 1

              Behavior on x {
                NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
              }
              Behavior on opacity {
                NumberAnimation { duration: 250 }
              }

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: Qt.formatDateTime(myClock.date, "MMMM yyyy")
                  color: root.cWhite
                  font.family: root.fontFamily
                  font.pixelSize: root.fontSize + 2
                }

                                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.weatherTemp + "  " + root.weatherDesc
                    color: root.cWhite
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize + 2
                    visible: root.weatherTemp !== ""
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.weatherCity
                    color: root.cGrayerGray
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 2
                    visible: root.weatherTemp !== ""
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.cGray
                    visible: root.weatherTemp !== ""
                }

                DayOfWeekRow {
                  Layout.fillWidth: true
                  locale: Qt.locale()

                  delegate: Text {
                    text: shortName
                    color: root.cGrayerGray
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 2
                    horizontalAlignment: Text.AlignHCenter
                  }
                }

            MonthGrid {
                Layout.fillWidth: true
                Layout.fillHeight: true
                month: myClock.date.getMonth()
                year: myClock.date.getFullYear()
                locale: Qt.locale()

                delegate: Text {
                    text: model.day
                    color: model.today ? root.cDarkGray : root.cWhite
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter

                    Rectangle {
                        z: -1
                        anchors.centerIn: parent
                        width: parent.height + 6
                        height: parent.height + 6
                        radius: width / 2
                        color: model.today ? root.cWhite : "transparent"
                    }
                }
            }
        }
    }
}

            Rectangle {
                anchors.fill: parent
                color: root.cDarkGray
                radius: root.cornerSize
                border.color: root.cGray
                border.width: 1
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 5

                    // ── clock ──
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48

                        Column {
    anchors.centerIn: parent
    spacing: -10

    Text {
        id: clockIcon
        anchors.horizontalCenter: parent.horizontalCenter
        text: ""
        color: clockMa.containsMouse ? "#0CEB8D" : root.cWhite
        font.family: root.fontFamily
        font.pixelSize: clockMa.pressed ? root.fontSize + 11
                      : clockMa.containsMouse ? root.fontSize + 18
                      : root.fontSize + 15

        Behavior on font.pixelSize {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDateTime(myClock.date, "hh:mm")
                                color: root.cWhite
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize - 1
                            }
                        }

                        MouseArea {
    id: clockMa
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.calVisible = !root.calVisible
}
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.preferredHeight: 1
                        color: root.cGray
                    }

// ── cpu ──
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48

                        Column {
                            anchors.centerIn: parent
                            spacing: -10

                            Text {
                                id: cpuIcon
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: ""
                                color: cpuMa.containsMouse ? "#FAE311" : root.cWhite
                                font.family: root.fontFamily
                                font.pixelSize: cpuMa.pressed ? root.fontSize + 11
                                              : cpuMa.containsMouse ? root.fontSize + 18
                                              : root.fontSize + 15

                                Behavior on font.pixelSize {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.cpuPct + "%"
                                color: root.cWhite
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize - 1
                            }
                        }

                        MouseArea {
                            id: cpuMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.statsVisible = !root.statsVisible
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.preferredHeight: 1
                        color: root.cGray
                    }

// ── memory ──
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48

                        Column {
                            anchors.centerIn: parent
                            spacing: -10

                            Text {
                                id: memIcon
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: ""
                                color: memMa.containsMouse ? "#0ECF08" : root.cWhite
                                font.family: root.fontFamily
                                font.pixelSize: memMa.pressed ? root.fontSize + 11
                                              : memMa.containsMouse ? root.fontSize + 18
                                              : root.fontSize + 15

                                Behavior on font.pixelSize {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.memPct + "%"
                                color: root.cWhite
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize - 1
                            }
                        }

                        MouseArea {
                            id: memMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.statsVisible = !root.statsVisible
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.preferredHeight: 1
                        color: root.cGray
                    }

// ── sound ──
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48

                        Column {
                            anchors.centerIn: parent
                            spacing: -10

                            Text {
                                id: soundIcon
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: ""
                                color: soundMa.containsMouse ? "#0CEBE7" : root.cWhite
                                font.family: root.fontFamily
                                font.pixelSize: soundMa.pressed ? root.fontSize + 11
                                              : soundMa.containsMouse ? root.fontSize + 18
                                              : root.fontSize + 15

                                Behavior on font.pixelSize {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.volume + "%"
                                color: root.cWhite
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize - 1
                            }
                        }

                        MouseArea {
                            id: soundMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.mediaVisible = !root.mediaVisible
                            onWheel: wheel => {
                                if (wheel.angleDelta.y > 0)
                                    Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", "5%+"])
                                else
                                    Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"])
                                volProc.running = true
                            }
                        }
                    }

                    Rectangle {
    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    Layout.preferredHeight: 1
    color: root.cGray
}

Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 48

    Text {
    anchors.centerIn: parent
    text: "󱄅"
    color: root.cWhite
    font.family: root.fontFamily
    font.pixelSize: root.fontSize + 25

    RotationAnimation on rotation {
        id: nixSpin
        running: nixMa.containsMouse
        loops: 1
        from: 0
        to: 360
        duration: 800
        easing.type: Easing.InOutCubic
    }
}

MouseArea {
    id: nixMa
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.launcherVisible = !root.launcherVisible
}}

Rectangle {
    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    Layout.preferredHeight: 1
    color: root.cGray
}

                    Item { Layout.fillHeight: true }

// ── tray ──
Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 48

    Text {
        anchors.centerIn: parent
        text: "󰀻"
        color: root.cWhite
        font.family: root.fontFamily
        font.pixelSize: root.fontSize + 25
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.trayVisible = !root.trayVisible
    }
}

                                        Rectangle {
                    Layout.fillWidth: true
             Layout.leftMargin: 8
           Layout.rightMargin: 8
           Layout.preferredHeight: 1
                   color: root.cGray
                          }


                    // ── workspaces ──
                    Item {
                      Layout.fillWidth: true
                      Layout.preferredHeight: 48

                      Text {
                        anchors.centerIn: parent
                        text: root.focusedWs ? root.wsIcon(root.focusedWs.id) : "?"
                        color: root.cWhite
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize + 10
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: {
                          root.wsVisible = true
                          wsHideTimer.stop()
                        }
                        onExited: wsHideTimer.restart()
                      }
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
      Description = "quickshell";
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
