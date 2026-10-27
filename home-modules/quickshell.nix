{ config ? {}, pkgs, ... }:
let
  animationsEnabled = config.wayland.windowManager.hyprland.settings.animations.enabled or true;

  workspaceBadgeQml = pkgs.writeText "WorkspaceBadge.qml" ''
    import QtQuick

    Item {
        id: badge

        property bool expanded: false
        property bool active: true
        property bool motionEnabled: true
        property int workspaceId: 1
        property real gap: 10
        property real minimumIconWidth: 16
        property int enterDuration: 300
        property int exitDuration: 220
        property real progress: 0
        property bool initialized: false
        property string displayedIcon: ""
        property string previousIcon: ""
        property real rollProgress: 1
        // Restored from the original shell; edit workspace icons here.
        property var icons: ({
            1: "", 2: "", 3: "󰆍", 4: "", 5: "", 6: "",
            7: "", 8: "", 9: "", 10: "",
            21: "", 22: "", 23: "", 24: ""
        })
        readonly property string icon: icons[workspaceId] ?? ""
        readonly property real iconWidth: Math.max(minimumIconWidth, measurement.implicitWidth)
        readonly property real expandedWidth: gap + iconWidth
        readonly property real revealWidth: progress * expandedWidth
        readonly property bool animating: resize.running
        readonly property bool rolling: roll.running

        implicitWidth: revealWidth
        clip: true

        function retarget() {
            resize.stop();
            const target = active && expanded ? 1 : 0;
            if (!active || !motionEnabled) {
                progress = target;
                return;
            }
            if (progress === target)
                return;
            resize.from = progress;
            resize.to = target;
            resize.duration = expanded ? enterDuration : exitDuration;
            resize.restart();
        }

        function settleRoll() {
            roll.stop();
            rollProgress = 1;
        }

        onIconChanged: {
            if (!initialized || icon === displayedIcon)
                return;
            // Only roll an icon that was already on screen. A first workspace
            // reveal still uses the capsule's existing expansion animation.
            const shouldRoll = active && motionEnabled && progress > 0;
            settleRoll();
            previousIcon = displayedIcon;
            displayedIcon = icon;
            if (shouldRoll) {
                rollProgress = 0;
                roll.restart();
            }
        }

        onExpandedChanged: retarget()
        onActiveChanged: {
            if (!active)
                settleRoll();
            retarget();
        }
        onMotionEnabledChanged: {
            if (!motionEnabled)
                settleRoll();
            retarget();
        }

        Component.onCompleted: {
            displayedIcon = icon;
            previousIcon = icon;
            initialized = true;
        }

        NumberAnimation {
            id: resize
            target: badge
            property: "progress"
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            id: roll
            target: badge
            property: "rollProgress"
            from: 0
            to: 1
            duration: 280
            easing.type: Easing.OutCubic
        }

        Text {
            id: measurement
            visible: false
            text: badge.icon
            font.family: "0xProto Nerd Font Mono"
            font.pixelSize: 16
        }

        Item {
            anchors.verticalCenter: parent.verticalCenter
            x: badge.gap + (1 - badge.progress) * 4
            width: badge.iconWidth
            height: measurement.implicitHeight
            opacity: badge.progress
            clip: true

            Text {
                anchors.centerIn: parent
                text: badge.displayedIcon
                font: measurement.font
                color: "#ffffff"
                opacity: badge.rolling ? badge.rollProgress : 1
                transform: Translate {
                    y: badge.rolling ? (1 - badge.rollProgress) * 6 : 0
                }
            }

            Text {
                anchors.centerIn: parent
                text: badge.previousIcon
                font: measurement.font
                color: "#ffffff"
                visible: badge.rolling
                opacity: 1 - badge.rollProgress
                transform: Translate { y: -badge.rollProgress * 6 }
            }
        }
    }
  '';

  hoverOutlineQml = pkgs.writeText "HoverOutline.qml" ''
    import QtQuick
    import QtQuick.Shapes

    Item {
        id: outline

        property bool hovered: false
        property bool active: true
        property bool pathVisible: true
        property bool motionEnabled: true
        property color strokeColor: "#ffffff"
        property real strokeWidth: 1.5
        property real inset: 3
        property real cornerRadius: Math.min(width, height) / 2
        property int enterDuration: 300
        property int exitDuration: 220
        property real progress: 0
        readonly property bool animating: travel.running

        readonly property real edgeInset: Math.max(strokeWidth / 2, inset)
        readonly property real innerWidth: Math.max(0, width - 2 * edgeInset)
        readonly property real innerHeight: Math.max(0, height - 2 * edgeInset)
        readonly property real radius: Math.max(0, Math.min(cornerRadius - edgeInset,
            innerWidth / 2, innerHeight / 2))
        readonly property real halfLength: innerWidth + innerHeight - 4 * radius
            + Math.PI * radius
        // Both halves meet at the left and right extremes when fully drawn.
        readonly property real trimStart: 0
        readonly property real trimEnd: progress

        function retarget() {
            travel.stop();
            const target = active && hovered ? 1 : 0;
            if (!active || !motionEnabled) {
                progress = target;
                return;
            }
            if (progress === target)
                return;
            travel.from = progress;
            travel.to = target;
            travel.duration = hovered ? enterDuration : exitDuration;
            travel.restart();
        }

        onHoveredChanged: retarget()
        onActiveChanged: retarget()
        onMotionEnabledChanged: retarget()

        NumberAnimation {
            id: travel
            target: outline
            property: "progress"
            easing.type: Easing.OutCubic
        }

        // Trim vector paths rather than clipping an outline with a rectangle:
        // the moving tips retain their round caps at every progress value.
        Shape {
            anchors.fill: parent
            visible: outline.pathVisible && outline.progress > 0 && outline.innerWidth > 0 && outline.innerHeight > 0
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: outline.strokeColor
                strokeWidth: outline.strokeWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                trim.start: outline.trimStart
                trim.end: outline.trimEnd
                startX: outline.edgeInset
                startY: outline.height / 2

                PathLine { x: outline.edgeInset; y: outline.edgeInset + outline.radius }
                PathArc {
                    x: outline.edgeInset + outline.radius; y: outline.edgeInset
                    radiusX: outline.radius; radiusY: outline.radius
                    direction: PathArc.Clockwise
                }
                PathLine { x: outline.width - outline.edgeInset - outline.radius; y: outline.edgeInset }
                PathArc {
                    x: outline.width - outline.edgeInset; y: outline.edgeInset + outline.radius
                    radiusX: outline.radius; radiusY: outline.radius
                    direction: PathArc.Clockwise
                }
                PathLine { x: outline.width - outline.edgeInset; y: outline.height / 2 }
            }

            ShapePath {
                strokeColor: outline.strokeColor
                strokeWidth: outline.strokeWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                trim.start: outline.trimStart
                trim.end: outline.trimEnd
                startX: outline.edgeInset
                startY: outline.height / 2

                PathLine { x: outline.edgeInset; y: outline.height - outline.edgeInset - outline.radius }
                PathArc {
                    x: outline.edgeInset + outline.radius; y: outline.height - outline.edgeInset
                    radiusX: outline.radius; radiusY: outline.radius
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: outline.width - outline.edgeInset - outline.radius; y: outline.height - outline.edgeInset }
                PathArc {
                    x: outline.width - outline.edgeInset; y: outline.height - outline.edgeInset - outline.radius
                    radiusX: outline.radius; radiusY: outline.radius
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: outline.width - outline.edgeInset; y: outline.height / 2 }
            }
        }
    }
  '';

  skyPositionsQml = pkgs.writeText "SkyPositions.qml" ''
    import QtQuick

    // Solar/lunar coordinates adapted from SunCalc 1.9.0 (BSD-2-Clause).
    // https://github.com/mourner/suncalc/tree/v1.9.0
    // Copyright (c) 2014, Vladimir Agafonkin
    // All rights reserved.
    //
    // Redistribution and use in source and binary forms, with or without modification, are
    // permitted provided that the following conditions are met:
    //
    //    1. Redistributions of source code must retain the above copyright notice, this list of
    //       conditions and the following disclaimer.
    //
    //    2. Redistributions in binary form must reproduce the above copyright notice, this list
    //       of conditions and the following disclaimer in the documentation and/or other materials
    //       provided with the distribution.
    //
    // THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
    // EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
    // MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    // COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
    // EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
    // SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
    // HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
    // TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
    // SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
    QtObject {
        id: sky
        property date now: new Date()
        property real latitude: 47.4979
        property real longitude: 19.0402
        readonly property var sun: position(now, false)
        readonly property var moon: position(now, true)

        function position(date, lunar) {
            const rad = Math.PI / 180;
            const days = date.valueOf() / 86400000 + 2440587.5 - 2451545;
            const obliquity = 23.4397 * rad;
            let lon, lat;
            if (lunar) {
                const meanLon = (218.316 + 13.176396 * days) * rad;
                const anomaly = (134.963 + 13.064993 * days) * rad;
                const argument = (93.272 + 13.229350 * days) * rad;
                lon = meanLon + 6.289 * rad * Math.sin(anomaly);
                lat = 5.128 * rad * Math.sin(argument);
            } else {
                const anomaly = (357.5291 + 0.98560028 * days) * rad;
                const center = rad * (1.9148 * Math.sin(anomaly)
                    + 0.02 * Math.sin(2 * anomaly) + 0.0003 * Math.sin(3 * anomaly));
                lon = anomaly + center + 102.9372 * rad + Math.PI;
                lat = 0;
            }
            const ascension = Math.atan2(Math.sin(lon) * Math.cos(obliquity)
                - Math.tan(lat) * Math.sin(obliquity), Math.cos(lon));
            const declination = Math.asin(Math.sin(lat) * Math.cos(obliquity)
                + Math.cos(lat) * Math.sin(obliquity) * Math.sin(lon));
            const hourAngle = rad * (280.16 + 360.9856235 * days + longitude) - ascension;
            const phi = latitude * rad;
            const up = Math.sin(phi) * Math.sin(declination)
                + Math.cos(phi) * Math.cos(declination) * Math.cos(hourAngle);
            const west = Math.cos(declination) * Math.sin(hourAngle);
            const phase = ((Math.atan2(west, up) / (2 * Math.PI)) % 1 + 1) % 1;
            return {phase: phase, altitude: Math.asin(Math.max(-1, Math.min(1, up))),
                azimuth: Math.atan2(Math.sin(hourAngle), Math.cos(hourAngle) * Math.sin(phi)
                    - Math.tan(declination) * Math.cos(phi))};
        }
    }
  '';

  celestialOutlineQml = pkgs.writeText "CelestialOutline.qml" ''
    import QtQuick

    HoverOutline {
        id: outline
        pathVisible: false
        property real sunPhase: 0
        property real moonPhase: 0.5
        property real iconSize: 10
        readonly property real perimeter: halfLength * 2
        readonly property var markers: layoutMarkers()

        function wrap(value) { return ((value % 1) + 1) % 1; }

        // Full arc starts at the leftmost point, clockwise. Both animation
        // branches still travel left-to-right, matching the original hover.
        function pointAt(fraction) {
            const r = radius;
            const straight = Math.max(0, innerWidth - 2 * r);
            let d = wrap(fraction) * perimeter;
            const quarter = Math.PI * r / 2;
            if (d < quarter) {
                const angle = Math.PI + d / Math.max(r, 0.001);
                return {x: edgeInset + r + r * Math.cos(angle),
                    y: height / 2 + r * Math.sin(angle)};
            }
            d -= quarter;
            if (d < straight)
                return {x: edgeInset + r + d, y: edgeInset};
            d -= straight;
            if (d < 2 * quarter) {
                const angle = -Math.PI / 2 + d / Math.max(r, 0.001);
                return {x: width - edgeInset - r + r * Math.cos(angle),
                    y: height / 2 + r * Math.sin(angle)};
            }
            d -= 2 * quarter;
            if (d < straight)
                return {x: width - edgeInset - r - d, y: height - edgeInset};
            d -= straight;
            const angle = Math.PI / 2 + d / Math.max(r, 0.001);
            return {x: edgeInset + r + r * Math.cos(angle),
                y: height / 2 + r * Math.sin(angle)};
        }

        function layoutMarkers() {
            let sun = wrap(sunPhase + 0.25), moon = wrap(moonPhase + 0.25);
            const delta = wrap(moon - sun + 0.5) - 0.5;
            const separation = (iconSize + 3) / Math.max(1, perimeter);
            // Near conjunction, separate the glyphs just enough to stay legible.
            if (Math.abs(delta) < separation) {
                const center = sun + delta / 2;
                const direction = delta < 0 ? -1 : 1;
                sun = wrap(center - direction * separation / 2);
                moon = wrap(center + direction * separation / 2);
            }
            return [{fraction: sun, glyph: ""}, {fraction: moon, glyph: ""}].map(marker => {
                const p = pointAt(marker.fraction);
                const reach = marker.fraction <= 0.5 ? marker.fraction * 2 : (1 - marker.fraction) * 2;
                return {x: p.x, y: p.y, fraction: marker.fraction, glyph: marker.glyph, reach: reach};
            });
        }

        function inGap(x, y) {
            const clearance = iconSize / 2 + 2;
            return markers.some(marker => Math.abs(x - marker.x) < clearance
                && Math.abs(y - marker.y) < clearance);
        }

        function iconOpacity(marker) {
            const span = (iconSize + 4) / Math.max(1, halfLength);
            const threshold = Math.max(0, Math.min(1 - span, marker.reach - span));
            return Math.max(0, Math.min(1, (progress - threshold) / span));
        }

        function repaint() { surface.requestPaint(); }
        onProgressChanged: repaint()
        onMarkersChanged: repaint()
        onWidthChanged: repaint()
        onHeightChanged: repaint()
        onVisibleChanged: if (visible) repaint()
        Component.onCompleted: repaint()

        Canvas {
            id: surface
            anchors.fill: parent
            visible: outline.progress > 0
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = outline.strokeColor;
                ctx.lineWidth = outline.strokeWidth;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                function branch(bottom) {
                    let drawing = false;
                    ctx.beginPath();
                    const count = Math.max(1, Math.ceil(outline.halfLength * outline.progress * 3));
                    for (let i = 0; i <= count; ++i) {
                        const distance = outline.progress * i / count / 2;
                        const p = outline.pointAt(bottom ? 1 - distance : distance);
                        if (outline.inGap(p.x, p.y)) {
                            drawing = false;
                        } else if (!drawing) {
                            ctx.moveTo(p.x, p.y);
                            drawing = true;
                        } else {
                            ctx.lineTo(p.x, p.y);
                        }
                    }
                    ctx.stroke();
                }
                branch(false);
                branch(true);
            }
        }

        Repeater {
            model: outline.markers
            delegate: Text {
                required property var modelData
                x: modelData.x - width / 2
                y: modelData.y - height / 2
                width: outline.iconSize; height: outline.iconSize
                text: modelData.glyph
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: outline.iconSize
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: "#ffffff"
                opacity: outline.iconOpacity(modelData)
                visible: outline.progress > 0
            }
        }
    }
  '';

  rollingClockQml = pkgs.writeText "RollingClock.qml" ''
    import QtQuick

    Item {
        id: face

        property bool clockMode: true
        property real fontSize: 12
        readonly property int characterCount: clockMode ? 5 : Math.max(1, timeText.length)
        property string timeText: "00:00"
        property bool active: true
        property bool motionEnabled: true
        property bool initialized: false
        property string displayedTime: ""
        property string previousTime: ""
        property real progress: 1
        property bool colonOn: true
        readonly property bool rolling: roll.running

        implicitWidth: measurement.implicitWidth
        implicitHeight: measurement.implicitHeight
        clip: true

        function digitChanged(index) {
            return (!clockMode || index !== 2) && previousTime.charAt(index) !== displayedTime.charAt(index);
        }

        function digitDimmed(index) {
            return rolling && (!clockMode || index !== 2) && !digitChanged(index) && displayedTime.charAt(index) !== " ";
        }

        function settle() {
            roll.stop();
            progress = 1;
        }

        onTimeTextChanged: {
            if (!initialized || timeText === displayedTime)
                return;
            settle();
            previousTime = displayedTime;
            displayedTime = timeText;
            if (active && motionEnabled) {
                progress = 0;
                roll.restart();
            }
        }

        onActiveChanged: {
            colonOn = true;
            if (!active)
                settle();
        }

        onMotionEnabledChanged: {
            colonOn = true;
            if (!motionEnabled)
                settle();
        }

        Component.onCompleted: {
            displayedTime = timeText;
            previousTime = timeText;
            initialized = true;
        }

        // Keep the original single-line font metrics and a fixed colon slot.
        Text {
            id: measurement
            visible: false
            text: face.clockMode ? "00:00" : "0".repeat(face.characterCount)
            font.family: "0xProto Nerd Font Mono"
            font.pixelSize: face.fontSize
            font.weight: Font.Normal
        }

        Timer {
            interval: 500
            repeat: true
            running: face.clockMode && face.active && face.motionEnabled
            onTriggered: face.colonOn = !face.colonOn
        }

        NumberAnimation {
            id: roll
            target: face
            property: "progress"
            from: 0
            to: 1
            duration: 280
            easing.type: Easing.OutCubic
        }

        Row {
            anchors.fill: parent
            spacing: 0

            Repeater {
                model: face.characterCount

                Item {
                    id: digit
                    required property int index
                    readonly property bool changing: face.digitChanged(index)
                    width: face.width / face.characterCount
                    height: face.height

                    Text {
                        anchors.centerIn: parent
                        text: face.displayedTime.charAt(digit.index)
                        font: measurement.font
                        color: face.digitDimmed(digit.index) ? "#888888" : "#ffffff"
                        opacity: face.clockMode && digit.index === 2 ? (face.colonOn ? 1 : 0)
                            : (digit.changing && face.rolling ? face.progress : 1)
                        transform: Translate {
                            y: digit.changing && face.rolling ? (1 - face.progress) * 6 : 0
                        }

                        Behavior on color {
                            enabled: face.active && face.motionEnabled
                            ColorAnimation { duration: 100 }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: face.previousTime.charAt(digit.index)
                        font: measurement.font
                        color: "#ffffff"
                        visible: digit.changing && face.rolling
                        opacity: 1 - face.progress
                        transform: Translate { y: -face.progress * 6 }
                    }
                }
            }
        }
    }
  '';

  visibilityQml = pkgs.writeText "ClockVisibility.qml" ''
    import QtQuick

    QtObject {
        id: state

        property bool idle: false
        property bool fullscreen: false
        property int workspaceId: 1
        readonly property bool workspaceReveal: workspaceTimer.running
        property bool workspaceTransition: false
        property bool cornerReveal: false
        property bool hovered: false
        property int lingerDuration: 2500
        readonly property bool hoverLinger: hoverLingerTimer.running
        readonly property bool menuLinger: menuLingerTimer.running
        property rect hoverBounds: Qt.rect(8, 8, 58, 31)
        readonly property int cornerWidth: 80
        readonly property int cornerHeight: 48
        readonly property bool compact: !fullscreen
            && (idle || workspaceReveal || workspaceTransition || cornerReveal || hovered || hoverLinger || menuLinger)

        // Workspace peeks have the same protected linger as hover. Key releases
        // and pointer movement must not cancel this timer.
        property Timer workspaceTimer: Timer { interval: state.lingerDuration }
        property Timer hoverLingerTimer: Timer { interval: state.lingerDuration }
        property Timer menuLingerTimer: Timer { interval: 2000 }

        function menuClosed() {
            if (!fullscreen)
                menuLingerTimer.restart();
        }

        onHoveredChanged: {
            if (hovered || fullscreen || lingerDuration <= 0)
                hoverLingerTimer.stop();
            else
                hoverLingerTimer.restart();
        }

        function workspaceChanged(id) {
            if (Number.isInteger(id))
                workspaceId = id;
            workspaceTimer.restart();
        }

        function cursorSample(x, y, monitorX, monitorY) {
            const inCorner = x >= monitorX && x < monitorX + cornerWidth
                && y >= monitorY && y < monitorY + cornerHeight;

            // Idle notifications do not identify the input device. A mouse can
            // keep sending movement while its coordinates are clamped at the
            // screen edge, so input must not cancel an intentional corner hover.
            cornerReveal = !fullscreen && inCorner;
            const localX = x - monitorX;
            const localY = y - monitorY;
            hovered = !fullscreen && localX >= hoverBounds.x
                && localX < hoverBounds.x + hoverBounds.width
                && localY >= hoverBounds.y && localY < hoverBounds.y + hoverBounds.height;
        }

        onFullscreenChanged: {
            if (fullscreen)
                workspaceTimer.stop();
            cornerReveal = false;
            hovered = false;
            hoverLingerTimer.stop();
            menuLingerTimer.stop();
        }
    }
  '';

  menuEntranceQml = pkgs.writeText "MenuEntrance.qml" ''
    import QtQuick

    QtObject {
        id: entrance
        property bool open: false
        property bool participates: true
        property bool motionEnabled: true
        property int order: 0
        property real distance: 80
        property real progress: 0
        readonly property real offset: -distance * (1-progress)
        readonly property bool animating: sequence.running
        function retarget() {
            sequence.stop();
            if (!participates || !motionEnabled) {
                progress = !participates || open ? 1 : 0;
                return;
            }
            const target = open ? 1 : 0;
            if (progress === target) return;
            pause.duration = open ? Math.max(0, order) * 65 : 0;
            slide.from = progress;
            slide.to = target;
            slide.duration = open ? 360 : 220;
            slide.easing.type = open ? Easing.OutCubic : Easing.InCubic;
            sequence.restart();
        }
        onOpenChanged: retarget()
        onParticipatesChanged: {
            // Switching from a pinned calendar clock to a new Windows opening
            // must prepare the offscreen position before open becomes true.
            if (participates && !open) {
                sequence.stop();
                progress = 0;
            } else retarget();
        }
        onMotionEnabledChanged: retarget()
        onOrderChanged: retarget()
        property SequentialAnimation sequence: SequentialAnimation {
            PauseAnimation {id: pause}
            NumberAnimation {id: slide;target:entrance;property:"progress"}
        }
    }
  '';

  sessionActionsQml = pkgs.writeText "SessionActions.qml" ''
    import QtQuick
    import Quickshell

    QtObject {
        id: actions
        property string pending: ""
        readonly property bool confirming: pending === "poweroff" || pending === "reboot"
        // The view owns dispatch. Tests can observe requests without running commands.
        signal commandRequested(var command)
        function request(action) {
            if (action === "poweroff" || action === "reboot") {
                pending = action;
            } else if (action === "rebuild") {
                pending = "";
                const directory = Quickshell.env("HOME") + "/nixos-config";
                commandRequested(["${pkgs.kitty}/bin/kitty", "--directory", directory,
                    directory + "/./rebuild.sh"]);
            }
        }
        function cancel() { pending = ""; }
        function confirm() {
            if (!confirming) return;
            const action = pending;
            pending = "";
            commandRequested(["${pkgs.systemd}/bin/systemctl", action]);
        }
    }
  '';

  expandedStateQml = pkgs.writeText "ExpandedState.qml" ''
    import QtQuick

    QtObject {
        id: state
        property bool open: false
        property string selected: ""
        property bool clockEntrance: false
        property bool motionEnabled: true
        property real progress: 0
        readonly property bool mounted: open || progress > 0 || transition.running
        readonly property bool animating: transition.running

        function openWith(module) {
            clockEntrance = module !== "clock";
            selected = module;
            open = true;
        }

        function toggle() {
            if (open)
                close();
            else
                openWith("");
        }

        function select(module) {
            if (!["clock", "media", "usage"].includes(module))
                return;
            selected = selected === module ? "" : module;
        }

        function collapse() { selected = ""; }

        function close() {
            selected = "";
            open = false;
        }

        function animate() {
            transition.stop();
            const target = open ? 1 : 0;
            if (!motionEnabled) {
                progress = target;
                return;
            }
            if (progress === target)
                return;
            transition.from = progress;
            transition.to = target;
            transition.duration = open ? 360 : 280;
            transition.easing.type = open ? Easing.OutCubic : Easing.InCubic;
            transition.restart();
        }

        onOpenChanged: animate()
        onMotionEnabledChanged: animate()

        property NumberAnimation transition: NumberAnimation {
            target: state
            property: "progress"
        }
    }
  '';

  moduleDeckQml = pkgs.writeText "ModuleDeck.qml" ''
    import QtQuick

    QtObject {
        id: deck
        property string requested: ""
        property string displayed: ""
        property bool motionEnabled: true
        property int enterDelay: 0
        property real progress: 0
        readonly property real contentProgress: Math.max(0, Math.min(1, (progress - 0.35) / 0.65))
        readonly property bool interactive: displayed !== "" && displayed === requested && progress > 0.98
        readonly property bool animating: sequence.running

        function retarget() {
            sequence.stop();
            if (!motionEnabled) {
                displayed = requested;
                progress = requested === "" ? 0 : 1;
                return;
            }
            if (progress === 0) displayed = requested;
            const opening = displayed !== "" && requested === displayed;
            const target = opening ? 1 : 0;
            if (progress === target) return;
            pause.duration = opening && progress === 0 ? enterDelay : 0;
            movement.from = progress;
            movement.to = target;
            movement.duration = opening ? 360 : 280;
            movement.easing.type = opening ? Easing.OutCubic : Easing.InCubic;
            sequence.restart();
        }
        onRequestedChanged: retarget()
        onMotionEnabledChanged: retarget()
        property SequentialAnimation sequence: SequentialAnimation {
            PauseAnimation { id: pause }
            NumberAnimation { id: movement; target: deck; property: "progress" }
            onFinished: {
                if (deck.progress === 0) {
                    deck.displayed = "";
                    if (deck.requested !== "") deck.retarget();
                }
            }
        }
    }
  '';

  moduleTileQml = pkgs.writeText "ModuleTile.qml" ''
    import QtQuick
    import QtQuick.Controls
    import Quickshell.Widgets

    Rectangle {
        id: tile
        property bool expanded: false
        property bool outlineEnabled: true
        property bool motionEnabled: true
        property real compactWidth: 58
        property real expandedWidth: 600
        property real expandedHeight: 310
        property string accessibleLabel: "Open module"
        property Item glassSource: null
        property point glassPosition: Qt.point(0, 0)
        property real glassOpacity: 0
        property real progress: 0
        property real controlledProgress: -1
        readonly property real reveal: controlledProgress >= 0 ? controlledProgress : progress
        readonly property bool animating: resize.running
        readonly property bool hovered: hitArea.containsMouse || pointer.visualFocus
        property bool wheelEnabled: false
        signal scrolled(real delta)
        signal clicked()

        width: compactWidth + (expandedWidth - compactWidth) * reveal
        height: 31 + (expandedHeight - 31) * reveal
        radius: 15.5 + 8.5 * reveal
        color: "#bf151515"
        antialiasing: true
        clip: true

        function retarget() {
            resize.stop();
            const target = expanded ? 1 : 0;
            if (!motionEnabled) {
                progress = target;
                return;
            }
            if (progress === target)
                return;
            resize.from = progress;
            resize.to = target;
            resize.duration = expanded ? 360 : 280;
            resize.easing.type = expanded ? Easing.OutCubic : Easing.InCubic;
            resize.restart();
        }

        onExpandedChanged: retarget()
        onMotionEnabledChanged: retarget()

        NumberAnimation {
            id: resize
            target: tile
            property: "progress"
        }

        ClippingRectangle {
            anchors.fill: parent
            radius: tile.radius
            color: "transparent"
            visible: tile.glassSource !== null
            opacity: tile.glassOpacity

            // Crop the already-blurred scene, preserving its screen alignment.
            // A module never samples the separately fading backdrop.
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: tile.glassSource
                sourceRect: Qt.rect(tile.glassPosition.x, tile.glassPosition.y,
                    tile.width, tile.height)
                live: tile.glassSource !== null
            }
            Rectangle { anchors.fill: parent; color: tile.color }
        }

        HoverOutline {
            anchors.fill: parent
            cornerRadius: tile.radius
            hovered: hitArea.containsMouse || pointer.visualFocus
            active: tile.outlineEnabled && tile.reveal === 0 && !tile.expanded
            motionEnabled: tile.motionEnabled
        }

        AbstractButton {
            id: pointer
            objectName: "compactButton"
            anchors.fill: parent
            z: 100
            visible: !tile.expanded && tile.reveal === 0
            enabled: visible
            hoverEnabled: true
            Accessible.name: tile.accessibleLabel
            background: Item {}
            contentItem: Item {}
            onClicked: tile.clicked()
            MouseArea {
                id: hitArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pointer.clicked()
                onWheel: event => {
                    if (tile.wheelEnabled) {
                        tile.scrolled(event.angleDelta.y);
                        event.accepted = true;
                    } else event.accepted = false;
                }
            }
        }
    }
  '';

  audioServiceQml = pkgs.writeText "AudioService.qml" ''
    import QtQuick
    import Quickshell
    import Quickshell.Io
    import Quickshell.Services.Pipewire

    Scope {
        id: audio
        property bool active: false
        property bool motionEnabled: true
        property var sink: Pipewire.defaultAudioSink
        readonly property bool available: !!sink && sink.ready && !!sink.audio
        readonly property real volume: available ? Math.max(0, sink.audio.volume) : 0
        readonly property bool muted: !available || sink.audio.muted
        readonly property string icon: muted || volume === 0 ? "󰝟"
            : volume < 0.34 ? "" : volume < 0.67 ? "" : ""
        readonly property string description: !available ? "Audio output unavailable"
            : muted ? "Media, muted" : "Media, volume " + Math.round(volume * 100) + " percent"
        readonly property bool capturing: active && motionEnabled && available && !muted && volume > 0
        readonly property int bandCount: 16
        property var bands: Array(bandCount).fill(0)
        property real wheelRemainder: 0

        // Native volume uses the same perceptual scale as wpctl. Never amplify
        // past 100%; preserve mute while scrolling, rather than unexpectedly unmuting.
        function scroll(delta) {
            if (!available || !Number.isFinite(delta))
                return;
            wheelRemainder += delta;
            const steps = Math.trunc(wheelRemainder / 120);
            if (steps === 0)
                return;
            wheelRemainder -= steps * 120;
            sink.audio.volume = Math.max(0, Math.min(1,
                Math.round((volume + steps * 0.05) * 10000) / 10000));
        }

        function setVolume(value) {
            if (available && Number.isFinite(value))
                sink.audio.volume = Math.max(0, Math.min(1, Math.round(value * 10000) / 10000));
        }

        function clear() {
            if (bands.some(value => value !== 0))
                bands = Array(bandCount).fill(0);
        }

        function acceptFrame(frame) {
            const values = frame.trim().split(";");
            if (values[values.length - 1] === "")
                values.pop();
            if (values.length !== bandCount || values.some(value => !/^\d+$/.test(value)))
                return false;
            const next = values.map(value => Math.max(0, Math.min(1, Number(value) / 1000)));
            if (next.some((value, i) => value !== bands[i]))
                bands = next;
            return true;
        }

        function spectrumConfig() {
            // Explicitly select this output's monitor, never a microphone/default input.
            const source = sink.name.replace(/[\r\n]/g, "") + ".monitor";
            return ["[general]", "framerate = 30", "bars = " + bandCount,
                "autosens = 1", "lower_cutoff_freq = 45", "higher_cutoff_freq = 16000",
                "[input]", "method = pipewire", "source = " + source,
                "[output]", "method = raw", "raw_target = /dev/stdout",
                "data_format = ascii", "ascii_max_range = 1000",
                "bar_delimiter = 59", "frame_delimiter = 10",
                "channels = mono", "mono_option = average",
                "[smoothing]", "noise_reduction = 35", ""].join("\n");
        }

        function syncCapture() {
            restart.stop();
            clear();
            if (spectrum.running)
                spectrum.running = false;
            else if (capturing)
                restart.restart();
        }

        onSinkChanged: { wheelRemainder = 0; syncCapture(); }
        onCapturingChanged: syncCapture()

        PwObjectTracker { objects: audio.sink ? [audio.sink] : [] }
        Process {
            id: spectrum
            command: ["${pkgs.cava}/bin/cava", "-p", "/dev/stdin"]
            onStarted: {
                write(audio.spectrumConfig());
                stdinEnabled = false;
            }
            stdout: SplitParser {
                onRead: data => { if (audio.capturing) audio.acceptFrame(data); }
            }
            onExited: {
                audio.clear();
                if (audio.capturing)
                    restart.restart();
            }
        }
        Timer {
            id: restart
            interval: 250
            onTriggered: if (audio.capturing && !spectrum.running) {
                spectrum.stdinEnabled = true;
                spectrum.running = true;
            }
        }
    }
  '';

  audioOutlineQml = pkgs.writeText "AudioOutline.qml" ''
    import QtQuick

    HoverOutline {
        id: outline
        pathVisible: false
        active: visible
        property bool muted: false
        property var bands: []
        readonly property real maximumBarLength: 10
        readonly property real overdraw: 8
        readonly property int barCount: 16

        // Equally spaced bands wrap the complete capsule, starting at bottom center.
        function pointAt(t) {
            const r = Math.max(0, Math.min(width, height) / 2 - inset);
            const straight = Math.max(0, width - 2 * inset - 2 * r);
            const perimeter = 2 * straight + 2 * Math.PI * r;
            let d = ((t % 1 + 1) % 1) * perimeter;
            const half = straight / 2;
            if (d < half)
                return {x: width / 2 - d, y: height - inset, nx: 0, ny: 1};
            d -= half;
            if (d < Math.PI * r) {
                const angle = Math.PI / 2 + d / Math.max(r, 0.001);
                return {x: inset + r + r * Math.cos(angle), y: height / 2 + r * Math.sin(angle),
                    nx: Math.cos(angle), ny: Math.sin(angle)};
            }
            d -= Math.PI * r;
            if (d < straight)
                return {x: inset + r + d, y: inset, nx: 0, ny: -1};
            d -= straight;
            if (d < Math.PI * r) {
                const angle = -Math.PI / 2 + d / Math.max(r, 0.001);
                return {x: width - inset - r + r * Math.cos(angle), y: height / 2 + r * Math.sin(angle),
                    nx: Math.cos(angle), ny: Math.sin(angle)};
            }
            d -= Math.PI * r;
            return {x: width - inset - r - d, y: height - inset, nx: 0, ny: 1};
        }

        function levelAt(t) {
            if (muted || !motionEnabled || bands.length === 0)
                return 0;
            // Interpolate one current FFT frame; no delayed samples around the rim.
            const pos = ((t % 1 + 1) % 1) * bands.length;
            const i = Math.floor(pos);
            const a = bands[i] || 0;
            const b = bands[(i + 1) % bands.length] || 0;
            const fraction = pos - i;
            const smooth = fraction * fraction * (3 - 2 * fraction);
            return Math.max(0, Math.min(1, a + (b - a) * smooth));
        }

        // Reveal both halves from the leftmost point toward the right, using
        // the same travel animation as the clock. Grow each round-capped bar
        // as the front reaches it instead of clipping or fading its pixels.
        function revealAt(t) {
            if (progress <= 0)
                return 0;
            const distance = ((t - 0.25) % 1 + 1) % 1;
            const reach = 2 * Math.min(distance, 1 - distance);
            const span = 2 / barCount;
            return Math.max(0, Math.min(1, (progress - Math.max(0, reach - span)) / span));
        }

        function repaint() { if (visible) surface.requestPaint(); }
        onBandsChanged: repaint()
        onMutedChanged: repaint()
        onProgressChanged: repaint()
        onVisibleChanged: repaint()
        onWidthChanged: repaint()
        onHeightChanged: repaint()
        Component.onCompleted: repaint()
        Connections {
            target: outline
            function onMotionEnabledChanged() { outline.repaint(); }
        }

        Canvas {
            id: surface
            visible: outline.progress > 0
            x: -outline.overdraw; y: -outline.overdraw
            width: outline.width + 2 * outline.overdraw
            height: outline.height + 2 * outline.overdraw
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.translate(outline.overdraw, outline.overdraw);
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.strokeStyle = "white";
                ctx.lineWidth = 1.5;
                const alpha = outline.muted ? 0.35 : 1;
                ctx.globalAlpha = alpha;
                for (let i = 0; i < outline.barCount; ++i) {
                    const t = i / outline.barCount;
                    const reveal = outline.revealAt(t);
                    if (reveal <= 0)
                        continue;
                    const p = outline.pointAt(t);
                    ctx.lineWidth = 1.5 * reveal;
                    const length = outline.maximumBarLength * outline.levelAt(t) * reveal;
                    ctx.beginPath();
                    const extent = Math.max(0.01, length / 2);
                    ctx.moveTo(p.x - p.nx * extent, p.y - p.ny * extent);
                    ctx.lineTo(p.x + p.nx * extent, p.y + p.ny * extent);
                    ctx.stroke();
                }
            }
        }
    }
  '';

  calendarViewQml = pkgs.writeText "CalendarView.qml" ''
    import QtQuick
    import QtQuick.Controls

    Item {
        id: calendar
        property date today: new Date()
        property int monthOffset: 0
        property date selectedDate: today
        readonly property date month: new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)
        readonly property string title: Qt.formatDateTime(month, "MMMM yyyy")
        readonly property int firstDay: (month.getDay() + 6) % 7
        readonly property int daysInMonth: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
        readonly property string selectedLabel: Qt.formatDateTime(selectedDate, "dddd, d MMMM")

        function dateAt(index) {
            return new Date(month.getFullYear(), month.getMonth(), index - firstDay + 1);
        }

        function sameDay(a, b) {
            return a.getFullYear() === b.getFullYear()
                && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
        }

        function reset() {
            monthOffset = 0;
            selectedDate = today;
        }

        Text {
            id: heading
            text: calendar.title
            color: "#ffffff"
            font.family: "0xProto Nerd Font Mono"
            font.pixelSize: 16
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: 3
        }

        Row {
            anchors.right: parent.right
            spacing: 3
            Repeater {
                model: ["‹", "›"]
                delegate: AbstractButton {
                    id: navigation
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    required property int index
                    required property string modelData
                    width: 28; height: 28
                    Accessible.name: index === 0 ? "Previous month" : "Next month"
                    onClicked: calendar.monthOffset += index === 0 ? -1 : 1
                    background: Rectangle {
                        radius: 14
                        color: navigation.hovered || navigation.visualFocus ? "#22ffffff" : "transparent"
                    }
                    contentItem: Text {
                        text: navigation.modelData
                        color: "#ffffff"
                        font.pixelSize: 24
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        Grid {
            id: weekdays
            y: 46
            columns: 7
            width: parent.width
            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]
                Text {
                    required property string modelData
                    width: weekdays.width / 7
                    height: 22
                    text: modelData
                    color: "#888888"
                    font.family: "0xProto Nerd Font Mono"
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Grid {
            id: days
            y: 70
            columns: 7
            width: parent.width
            Repeater {
                model: 42
                delegate: AbstractButton {
                    id: day
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    required property int index
                    readonly property date value: calendar.dateAt(index)
                    readonly property bool inMonth: value.getMonth() === calendar.month.getMonth()
                    readonly property bool isToday: calendar.sameDay(value, calendar.today)
                    readonly property bool chosen: calendar.sameDay(value, calendar.selectedDate)
                    width: days.width / 7
                height: 28
                    Accessible.name: Qt.formatDateTime(value, "dddd, d MMMM yyyy")
                    onClicked: calendar.selectedDate = value
                    background: Rectangle {
                        anchors.centerIn: parent
                        width: 27; height: 27; radius: 13.5
                        color: day.isToday ? "#ffffff"
                            : day.chosen || day.hovered || day.visualFocus ? "#28ffffff" : "transparent"
                    }
                    contentItem: Text {
                        text: day.value.getDate()
                        color: day.isToday ? "#151515" : day.inMonth ? "#ffffff" : "#666666"
                        font.family: "0xProto Nerd Font Mono"
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        AbstractButton {
            id: todayButton
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: parent.width
            height: 25
            Accessible.name: "Return to today"
            onClicked: calendar.reset()
            background: Rectangle { color: "transparent" }
            contentItem: Text {
                text: calendar.selectedLabel
                color: todayButton.hovered || todayButton.visualFocus ? "#ffffff" : "#aaaaaa"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 10
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }
  '';

  weatherServiceQml = pkgs.writeText "WeatherService.qml" ''
    import QtQuick

    QtObject {
        id: weather
        property bool active: false
        property bool loading: false
        property bool available: false
        property bool stale: false
        property string city: "Budapest"
        property real latitude: 47.4979
        property real longitude: 19.0402
        property real temperature: 0
        property real feelsLike: 0
        property real wind: 0
        property int code: 0
        property bool daylight: true
        property double updatedAt: 0
        property var request: null
        readonly property string condition: describe(code)
        readonly property string icon: code === 0 ? (daylight ? "" : "")
            : code <= 3 ? "" : code <= 48 ? "󰖑" : code <= 67 ? "󰖗"
            : code <= 77 ? "" : code <= 82 ? "󰖖" : code <= 86 ? "" : ""
        readonly property string temperatureText: available ? Math.round(temperature) + "°" : "—"
        readonly property string status: available ? (stale ? "Last update unavailable" : condition)
            : loading ? "Loading weather…" : "Weather unavailable"

        function describe(value) {
            if (value === 0) return "Clear sky";
            if (value === 1) return "Mostly clear";
            if (value === 2) return "Partly cloudy";
            if (value === 3) return "Overcast";
            if (value <= 48) return "Fog";
            if (value <= 57) return "Drizzle";
            if (value <= 67) return "Rain";
            if (value <= 77) return "Snow";
            if (value <= 82) return "Rain showers";
            if (value <= 86) return "Snow showers";
            return "Thunderstorm";
        }

        function accept(payload) {
            const current = payload.current;
            if (!current || !Number.isFinite(current.temperature_2m)
                || !Number.isFinite(current.apparent_temperature)
                || !Number.isFinite(current.wind_speed_10m)
                || !Number.isInteger(current.weather_code))
                throw new Error("Incomplete weather response");
            temperature = current.temperature_2m;
            feelsLike = current.apparent_temperature;
            wind = current.wind_speed_10m;
            code = current.weather_code;
            daylight = current.is_day === 1;
            updatedAt = Date.now();
            available = true;
            stale = false;
        }

        function refresh() {
            if (loading)
                return;
            loading = true;
            const xhr = new XMLHttpRequest();
            request = xhr;
            xhr.open("GET", "https://api.open-meteo.com/v1/forecast?latitude=" + latitude
                + "&longitude=" + longitude
                + "&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m"
                + "&timezone=Europe%2FBudapest&forecast_days=1");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE || weather.request !== xhr)
                    return;
                timeout.stop();
                try {
                    if (xhr.status !== 200)
                        throw new Error("Weather request failed");
                    weather.accept(JSON.parse(xhr.responseText));
                } catch (error) {
                    weather.stale = weather.available;
                }
                weather.loading = false;
                weather.request = null;
            };
            timeout.restart();
            xhr.send();
        }

        onActiveChanged: if (active && Date.now() - updatedAt >= 600000) refresh()

        property Timer refreshTimer: Timer {
            interval: 600000
            repeat: true
            running: weather.active
            onTriggered: weather.refresh()
        }

        property Timer timeout: Timer {
            interval: 10000
            onTriggered: {
                const xhr = weather.request;
                weather.request = null;
                weather.loading = false;
                weather.stale = weather.available;
                if (xhr) xhr.abort();
            }
        }
    }
  '';

  backdropGeometryQml = pkgs.writeText "BackdropGeometry.qml" ''
    import QtQuick

    QtObject {
        property real viewportWidth: 1920
        property real viewportHeight: 1080
        property var cutouts: []
        property real cutoutOverlap: 1
        readonly property real fadeWidth: viewportWidth * 0.5
        readonly property string maskPath: roundedRect(0, 0, fadeWidth, viewportHeight, 0)
            + cutouts.filter(rect => rect.width > 0 && rect.height > 0)
                .map(rect => moduleCutout(rect)).join(" ")

        function moduleCutout(rect) {
            // Back the antialiased module rim with blur instead of exposing
            // sharp desktop pixels between two independently rendered masks.
            const inset = Math.max(0, cutoutOverlap);
            if (rect.width <= inset * 2 || rect.height <= inset * 2)
                return "";
            return roundedRect(rect.x + inset, rect.y + inset,
                rect.width - inset * 2, rect.height - inset * 2,
                Math.max(0, rect.radius - inset));
        }

        function roundedRect(x, y, width, height, radius) {
            const r = Math.max(0, Math.min(radius, width / 2, height / 2));
            if (r === 0)
                return "M " + x + " " + y + " h " + width + " v " + height + " h " + (-width) + " z ";
            // SVG circular arcs match Rectangle/ClippingRectangle corners;
            // quadratic approximations leave crescent-shaped gaps at the join.
            return "M " + (x + r) + " " + y + " h " + (width - 2 * r)
                + " a " + r + " " + r + " 0 0 1 " + r + " " + r
                + " v " + (height - 2 * r) + " a " + r + " " + r + " 0 0 1 " + (-r) + " " + r
                + " h " + (2 * r - width) + " a " + r + " " + r + " 0 0 1 " + (-r) + " " + (-r)
                + " v " + (2 * r - height) + " a " + r + " " + r + " 0 0 1 " + r + " " + (-r) + " z ";
        }

        function windowVisible(client, workspaceActive, screenX, screenY) {
            if (!client.mapped || client.hidden || (!workspaceActive && !client.pinned)
                || !client.at || !client.size || client.size[0] <= 0 || client.size[1] <= 0)
                return false;
            // Keep blur-kernel padding beyond the fade; never crop a source before
            // blurring or stretch the left part of a full-window capture.
            return client.at[0] < screenX + fadeWidth + 96
                && client.at[0] + client.size[0] > screenX - 96
                && client.at[1] < screenY + viewportHeight
                && client.at[1] + client.size[1] > screenY;
        }

        function stackingOrder(client) {
            return 100000 + (client.fullscreen ? 2000000 : client.floating ? 1000000 : 0)
                - Math.min(99999, client.focusHistoryID ?? 99999);
        }
    }
  '';

  frostedBackdropQml = pkgs.writeText "FrostedBackdrop.qml" ''
    import QtQuick
    import QtQuick.Effects
    import QtQuick.Shapes
    import Quickshell
    import Quickshell.Hyprland
    import Quickshell.Wayland

    Item {
        id: backdrop
        property var screen: null
        property bool active: false
        property real reveal: 0
        property real viewportWidth: 1920
        property var cutouts: []
        property url wallpaper: "${../wallpaper/wallpaper.png}"
        readonly property alias blurredScene: uniformBlur
        readonly property int liveSourceCount: !active ? 0 : Hyprland.toplevels.values.filter(window =>
            geometry.windowVisible(window.lastIpcObject, window.workspace?.active ?? false,
                screen?.x ?? 0, screen?.y ?? 0) && window.wayland !== null).length
        width: geometry.fadeWidth
        clip: true
        opacity: reveal

        BackdropGeometry {
            id: geometry
            viewportWidth: backdrop.viewportWidth
            viewportHeight: backdrop.height
            cutouts: backdrop.cutouts
        }

        // Each stream exports an application surface, never the output containing
        // this shell. Moving content stays live without recursively blurring the UI.
        Item {
            id: scene
            width: backdrop.viewportWidth
            height: backdrop.height

            Image {
                anchors.fill: parent
                source: backdrop.wallpaper
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            Repeater {
                // Keep delegates stable while IPC geometry refreshes. Rebuilding a
                // filtered array here would restart every capture stream each tick.
                model: Hyprland.toplevels
                delegate: ScreencopyView {
                    id: stream
                    required property var modelData
                    readonly property var client: modelData.lastIpcObject
                    readonly property bool onScreen: geometry.windowVisible(client,
                        modelData.workspace?.active ?? false, backdrop.screen?.x ?? 0,
                        backdrop.screen?.y ?? 0)
                    x: (client.at?.[0] ?? 0) - (backdrop.screen?.x ?? 0)
                    y: (client.at?.[1] ?? 0) - (backdrop.screen?.y ?? 0)
                    width: Math.max(1, client.size?.[0] ?? 1)
                    height: Math.max(1, client.size?.[1] ?? 1)
                    z: geometry.stackingOrder(client)
                    captureSource: backdrop.active && onScreen ? modelData.wayland : null
                    live: true
                    paintCursor: false
                    visible: onScreen
                }
            }
        }

        ShaderEffectSource {
            id: sceneTexture
            sourceItem: scene
            hideSource: true
            visible: false
            live: backdrop.active
        }

        Item {
            id: fadeMask
            width: backdrop.viewportWidth
            height: backdrop.height

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillRule: ShapePath.OddEvenFill
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: geometry.fadeWidth; y2: 0
                        GradientStop { position: 0; color: "#ffffff" }
                        GradientStop { position: 0.25; color: "#efffffff" }
                        GradientStop { position: 0.65; color: "#70ffffff" }
                        GradientStop { position: 1; color: "#00ffffff" }
                    }
                    PathSvg { path: geometry.maskPath }
                }
            }
        }

        ShaderEffectSource {
            id: maskTexture
            sourceItem: fadeMask
            hideSource: true
            visible: false
        }

        MultiEffect {
            id: uniformBlur
            width: backdrop.viewportWidth
            height: backdrop.height
            source: sceneTexture
            blurEnabled: true
            blur: 1
            blurMax: 48
            autoPaddingEnabled: false
        }

        ShaderEffectSource {
            id: blurredTexture
            sourceItem: uniformBlur
            hideSource: true
            visible: false
            live: backdrop.active
        }

        MultiEffect {
            width: backdrop.viewportWidth
            height: backdrop.height
            source: blurredTexture
            visible: backdrop.active
            autoPaddingEnabled: false
            colorization: 0.15
            colorizationColor: "#151515"
            maskEnabled: true
            maskSource: maskTexture
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.5
        }

        onActiveChanged: if (active) Hyprland.refreshToplevels()
        Timer {
            interval: 100
            repeat: true
            running: backdrop.active
            onTriggered: Hyprland.refreshToplevels()
        }
    }
  '';

  clockDetailsQml = pkgs.writeText "ClockDetails.qml" ''
    import QtQuick
    import QtQuick.Controls

    Item {
        id: details
        property date now: new Date()
        required property var weather
        readonly property alias calendar: calendar

        CalendarView {
            id: calendar
            x: 22; y: 22
            width: 278; height: 266
            today: details.now
        }

        Rectangle {
            x: 318; y: 30
            width: 1; height: 248
            color: "#16ffffff"
        }

        Item {
            x: 340; y: 22
            width: 238; height: 266

            Text {
                anchors.top: parent.top
                anchors.topMargin: 18
                text: Qt.formatDateTime(details.now, "HH:mm:ss")
                color: "#ffffff"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 33
            }

            Text {
                y: 65
                text: Qt.formatDateTime(details.now, "t")
                color: "#888888"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 10
            }

            Text {
                y: 113
                text: details.weather.city
                color: "#aaaaaa"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 11
            }

            Text {
                y: 134
                text: details.weather.temperatureText
                color: "#ffffff"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 38
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 8
                y: 141
                text: details.weather.available ? details.weather.icon : ""
                color: details.weather.available ? "#ffffff" : "#777777"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 31
            }

            Text {
                y: 185
                width: parent.width
                text: details.weather.status
                color: "#bbbbbb"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            Text {
                y: 208
                text: details.weather.available
                    ? "Feels " + Math.round(details.weather.feelsLike) + "°  ·  "
                        + Math.round(details.weather.wind) + " km/h" : ""
                color: "#888888"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 10
            }

            AbstractButton {
                id: credit
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                y: 240
                width: parent.width; height: 26
                Accessible.name: details.weather.available ? "Weather by Open-Meteo" : "Retry weather"
                onClicked: {
                    if (details.weather.available)
                        Qt.openUrlExternally("https://open-meteo.com/");
                    else
                        details.weather.refresh();
                }
                background: Rectangle { color: "transparent" }
                contentItem: Text {
                    text: details.weather.available ? "Open-Meteo ↗" : details.weather.loading ? "Open-Meteo" : "Retry ↻  ·  Open-Meteo"
                    color: credit.hovered || credit.visualFocus ? "#ffffff" : "#777777"
                    font.family: "0xProto Nerd Font Mono"
                    font.pixelSize: 9
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
  '';

  playlistBackendPython = pkgs.writeText "PlaylistBackend.py" ''
    """Quickshell playlist library: JSON-lines control, yt-dlp audio, mpv IPC."""
    import argparse
    import json
    import math
    import os
    from pathlib import Path
    import re
    import shutil
    import signal
    import socket
    import subprocess
    import sys
    import tempfile
    import threading
    import time
    from urllib.parse import parse_qs, quote, urlparse

    MEDIA_EXTENSIONS = {'.opus', '.ogg', '.mp3', '.m4a', '.flac', '.wav', '.webm', '.mp4', '.aac'}
    MANIFEST = '.quickshell-playlist.json'


    def read_json(path, default):
        try:
            return json.loads(path.read_text())
        except (OSError, ValueError):
            return default


    def atomic_json(path, value):
        tmp = path.with_name(path.name + '.tmp')
        tmp.write_text(json.dumps(value, ensure_ascii=False))
        tmp.replace(path)


    def playlist_url(value):
        parsed = urlparse(value.strip())
        if parsed.scheme not in {'https', 'http'} or parsed.hostname not in {
            'youtube.com', 'www.youtube.com', 'music.youtube.com', 'm.youtube.com', 'youtu.be'
        }:
            raise ValueError('Enter a YouTube playlist URL')
        key = parse_qs(parsed.query).get('list', ['''])[0]
        if not re.fullmatch(r'[A-Za-z0-9_-]{6,160}', key):
            raise ValueError('The URL needs a playlist ID')
        return key, 'https://www.youtube.com/playlist?list=' + key


    def terminate(process):
        if process and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=2)
            except ProcessLookupError:
                pass


    class Player:
        def __init__(self, changed, ended, binary='mpv', extra_args=()):
            self.changed, self.ended = changed, ended
            self.binary, self.extra_args = binary, list(extra_args)
            self.process = self.connection = self.directory = None
            self.send_lock = threading.Lock()
            self.connected = threading.Event()
            self.closing = False
            self.generation = 0
            self.paused = False
            self.idle = True
            self.pause_requested = False

        def ensure(self):
            if self.process and self.process.poll() is None and self.connected.is_set():
                return
            self.close()
            self.closing = False
            self.connected.clear()
            self.directory = tempfile.TemporaryDirectory(prefix='quickshell-music-', dir=os.environ.get('XDG_RUNTIME_DIR'))
            path = str(Path(self.directory.name) / 'mpv.sock')
            self.process = subprocess.Popen([
                self.binary, '--no-config', '--no-video', '--idle=yes', '--no-terminal',
                '--input-terminal=no', '--audio-display=no', '--volume=100',
                '--input-ipc-server=' + path, *self.extra_args
            ], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            threading.Thread(target=self.listen, args=(path, self.generation), daemon=True).start()
            if not self.connected.wait(4):
                self.close()
                raise RuntimeError('Could not start the music player')

        def listen(self, path, generation):
            connection = socket.socket(socket.AF_UNIX)
            try:
                for _ in range(80):
                    if self.closing:
                        return
                    try:
                        connection.connect(path)
                        break
                    except OSError:
                        time.sleep(.05)
                else:
                    return
                self.connection = connection
                self.connected.set()
                self.send(['observe_property', 1, 'pause'])
                self.send(['observe_property', 2, 'idle-active'])
                self.send(['observe_property', 3, 'time-pos'])
                self.send(['observe_property', 4, 'duration'])
                with connection.makefile('r') as stream:
                    for line in stream:
                        if generation != self.generation:
                            break
                        event = json.loads(line)
                        if event.get('event') == 'property-change':
                            if event.get('name') == 'pause':
                                self.paused = bool(event.get('data'))
                                self.changed(playing=not self.paused and not self.idle)
                            elif event.get('name') == 'idle-active':
                                self.idle = bool(event.get('data'))
                                self.changed(playing=not self.idle and not self.paused)
                            elif event.get('name') in {'time-pos', 'duration'}:
                                value = event.get('data')
                                if isinstance(value, (int, float)) and math.isfinite(value):
                                    key = 'position' if event['name'] == 'time-pos' else 'duration'
                                    self.changed(**{key: max(0, value)})
                        elif event.get('event') == 'end-file':
                            if event.get('reason') == 'eof' and not self.closing:
                                self.ended()
                            elif event.get('reason') == 'error':
                                self.changed(playing=False, error='Playback failed')
            except (OSError, ValueError):
                pass
            finally:
                connection.close()
                if generation == self.generation:
                    self.connected.clear()
                    if not self.closing:
                        self.changed(playing=False, loaded=False)

        def send(self, command):
            with self.send_lock:
                if not self.connection:
                    raise RuntimeError('Music player is not connected')
                self.connection.sendall((json.dumps({'command': command}) + '\n').encode())

        def set_paused(self, value):
            self.pause_requested = bool(value)
            self.send(['set_property', 'pause', self.pause_requested])

        def load(self, path, paused=False):
            self.ensure()
            self.set_paused(paused)
            self.send(['loadfile', str(path), 'replace'])

        def close(self):
            self.generation += 1
            self.closing = True
            if self.connection:
                try:
                    self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                self.connection = None
            terminate(self.process)
            self.process = None
            self.connected.clear()
            if self.directory:
                self.directory.cleanup()
                self.directory = None


    class Library:
        def __init__(self, root, emit=lambda value: None, yt_dlp='yt-dlp', ffmpeg='ffmpeg', mpv='mpv', node='node', player_args=()):
            self.root = Path(root).expanduser().resolve()
            self.root.mkdir(parents=True, exist_ok=True)
            self.emit_callback, self.yt_dlp, self.ffmpeg, self.node = emit, yt_dlp, ffmpeg, node
            self.lock = threading.RLock()
            self.playlists = {}
            self.selected = read_json(self.root / '.state.json', {}).get('selected', ''')
            self.current = {'loaded': False, 'playing': False, 'playlist': ''', 'track': '''}
            self.position_emitted_at = 0
            self.error = '''
            self.busy = False
            self.cancelled = threading.Event()
            self.closing = threading.Event()
            self.download_process = None
            self.player = Player(self.player_changed, lambda: self.next_track(1), mpv, player_args)
            self.scan()

        def folder(self, key):
            if not key or key.startswith('.') or Path(key).name != key:
                raise ValueError('Invalid playlist')
            folder = self.root / key
            if folder.is_symlink() or folder.resolve().parent != self.root or not folder.is_dir():
                raise ValueError('Playlist is unavailable')
            return folder

        def track_path(self, folder, name):
            path = folder / name
            if Path(name).name != name or path.is_symlink() or path.resolve().parent != folder.resolve():
                raise ValueError('Invalid track path')
            return path

        def scan(self):
            with self.lock:
                playlists = {}
                for folder in sorted(self.root.iterdir(), key=lambda p: p.name.casefold()):
                    if not folder.is_dir() or folder.is_symlink() or folder.name.startswith('.'):
                        continue
                    stored = read_json(folder / MANIFEST, {})
                    tracks = stored.get('tracks', []) if stored else []
                    if not tracks:
                        tracks = [{'id': p.name, 'title': p.stem, 'artist': ''', 'file': p.name,
                                   'art': ''', 'skipped': False, 'state': 'ready', 'progress': 1}
                                  for p in sorted(folder.iterdir()) if p.suffix.lower() in MEDIA_EXTENSIONS and not p.is_symlink()]
                    for track in tracks:
                        try:
                            ready = bool(track.get('file')) and self.track_path(folder, track['file']).is_file()
                        except ValueError:
                            ready = False
                        track['state'] = 'ready' if ready else 'failed' if track.get('state') == 'failed' else 'queued'
                        track['progress'] = 1 if ready else 0
                    if tracks or stored:
                        playlists[folder.name] = {'id': folder.name, 'title': stored.get('title', folder.name),
                                                 'source': stored.get('source', '''), 'tracks': tracks}
                self.playlists = playlists
                if self.selected not in playlists:
                    self.selected = next(iter(playlists), ''')

        def save(self, key):
            playlist = self.playlists[key]
            atomic_json(self.folder(key) / MANIFEST, playlist)
            atomic_json(self.root / '.state.json', {'selected': self.selected})

        def snapshot(self):
            with self.lock:
                selected = self.playlists.get(self.selected, {})
                return json.loads(json.dumps({'selected': self.selected, 'tracks': selected.get('tracks', []),
                    'title': selected.get('title', '''), 'source': selected.get('source', '''),
                    'playlists': [{'id': p['id'], 'title': p['title'], 'count': len(p['tracks']),
                                   'art': next((t.get('art', ''') for t in p['tracks'] if t.get('art')), ''')}
                                  for p in self.playlists.values()],
                    'current': self.current, 'busy': self.busy, 'error': self.error}))

        def emit(self):
            if not self.closing.is_set():
                self.emit_callback(self.snapshot())

        def player_changed(self, **values):
            with self.lock:
                if 'error' in values:
                    self.error = values.pop('error')
                self.current.update(values)
                # mpv emits time-pos frequently; limit full library frames to four/sec.
                if set(values) == {'position'}:
                    now = time.monotonic()
                    if now - self.position_emitted_at < .25:
                        return
                    self.position_emitted_at = now
            self.emit()

        def select(self, key):
            with self.lock:
                self.folder(key)
                if key not in self.playlists:
                    raise ValueError('Playlist is unavailable')
                self.selected = key
                self.error = '''
                atomic_json(self.root / '.state.json', {'selected': key})
            self.emit()

        def play(self, track_id=''', playlist_id=''', paused=False):
            with self.lock:
                key = playlist_id or self.selected
                playlist = self.playlists.get(key, {})
                tracks = [t for t in playlist.get('tracks', []) if t.get('state') == 'ready' and not t.get('skipped')]
                track = next((t for t in tracks if t['id'] == track_id), None) if track_id else next(iter(tracks), None)
                if not track:
                    raise ValueError('No playable track selected')
                path = self.track_path(self.folder(key), track['file'])
                if not path.is_file():
                    raise ValueError('Track is unavailable')
                self.current = {**track, 'playlist': key, 'track': track['id'], 'loaded': True, 'playing': not paused, 'position': 0, 'duration': 0}
                self.error = '''
            try:
                self.player.load(path, paused)
            except Exception:
                self.player_changed(playing=False, loaded=False)
                raise
            self.emit()

        def next_track(self, direction, paused=None):
            with self.lock:
                key = self.current.get('playlist') or self.selected
                tracks = self.playlists.get(key, {}).get('tracks', [])
                current = next((i for i, t in enumerate(tracks) if t['id'] == self.current.get('track')), -1)
                for step in range(1, len(tracks) + 1):
                    candidate = tracks[(current + step * direction) % len(tracks)]
                    if candidate.get('state') == 'ready' and not candidate.get('skipped'):
                        target = candidate['id']
                        break
                else:
                    self.player.close()
                    self.player_changed(loaded=False, playing=False)
                    return
            self.play(target, key, self.player.pause_requested if paused is None else paused)

        def skip(self, track_id):
            with self.lock:
                playlist = self.playlists[self.selected]
                track = next((t for t in playlist['tracks'] if t['id'] == track_id), None)
                if not track:
                    raise ValueError('Track is unavailable')
                track['skipped'] = not track.get('skipped', False)
                advance = track['skipped'] and self.current.get('playlist') == self.selected and self.current.get('track') == track_id
                self.save(self.selected)
            if advance:
                self.next_track(1)
            self.emit()

        def delete(self):
            with self.lock:
                if self.busy:
                    raise ValueError('Wait for the download to finish')
                key = self.selected
                folder = self.folder(key)
                if self.current.get('playlist') == key:
                    self.player.close()
                    self.current = {'loaded': False, 'playing': False, 'playlist': ''', 'track': '''}
                trash = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'Trash'
                (trash / 'files').mkdir(parents=True, exist_ok=True)
                (trash / 'info').mkdir(parents=True, exist_ok=True)
                name = key + '-' + str(time.time_ns())
                shutil.move(str(folder), trash / 'files' / name)
                (trash / 'info' / (name + '.trashinfo')).write_text('[Trash Info]\nPath=' + quote(str(folder)) + '\nDeletionDate=' + time.strftime('%Y-%m-%dT%H:%M:%S') + '\n')
                self.playlists.pop(key)
                self.selected = next(iter(self.playlists), ''')
                atomic_json(self.root / '.state.json', {'selected': self.selected})
            self.emit()

        def base_command(self):
            return [self.yt_dlp, '--ignore-config', '--js-runtimes', 'node:' + self.node,
                    '--socket-timeout', '15', '--retries', '2', '--extractor-retries', '2']

        def start_download(self, url):
            _, url = playlist_url(url)
            with self.lock:
                if self.busy:
                    raise ValueError('A playlist is already downloading')
                self.busy, self.error = True, '''
                self.cancelled.clear()
            self.emit()
            threading.Thread(target=self.download, args=(url,), daemon=True).start()

        def spawn(self, args):
            if self.cancelled.is_set() or self.closing.is_set():
                raise RuntimeError('Download cancelled')
            process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                       encoding='utf-8', errors='replace', start_new_session=True)
            self.download_process = process
            if self.cancelled.is_set() or self.closing.is_set():
                terminate(process)
                raise RuntimeError('Download cancelled')
            return process

        def download(self, url):
            key = None
            try:
                process = self.spawn(self.base_command() + ['--flat-playlist', '--dump-single-json', '--ignore-errors', '--no-warnings', '--', url])
                output, _ = process.communicate(timeout=120)
                if process.returncode:
                    raise RuntimeError('Could not read the playlist')
                try:
                    data = json.loads(output)
                except ValueError:
                    raise RuntimeError('Could not read the playlist') from None
                source_id, _ = playlist_url(url)
                title = str(data.get('title') or source_id)
                entries = [entry for entry in data.get('entries') or [] if entry and re.fullmatch(r'[A-Za-z0-9_-]{11}', str(entry.get('id', ''')))]
                if not entries:
                    raise ValueError('The playlist has no available tracks')
                with self.lock:
                    key = next((k for k, p in self.playlists.items() if p.get('source') == url), None)
                    if key is None:
                        clean = re.sub(r'[^\w .-]', ''', title).strip(' .')[:70] or 'Playlist'
                        key = clean + ' [' + source_id + ']'
                        folder = self.root / key
                        if folder.exists():
                            raise ValueError('A different playlist already uses this folder')
                        folder.mkdir()
                        self.playlists[key] = {'id': key, 'title': title, 'source': url, 'tracks': []}
                    folder = self.folder(key)
                    old = {t['id']: t for t in self.playlists[key]['tracks']}
                    tracks = []
                    for entry in entries:
                        track_id = entry['id']
                        prior = old.get(track_id, {})
                        file = prior.get('file', track_id + '.opus')
                        ready = self.track_path(folder, file).is_file()
                        thumb = next((t.get('url', ''') for t in reversed(entry.get('thumbnails') or []) if t.get('url')), ''')
                        tracks.append({'id': track_id, 'title': entry.get('title') or track_id,
                            'artist': prior.get('artist') or entry.get('uploader') or entry.get('channel') or ''',
                            'file': file, 'art': prior.get('art') or thumb, 'skipped': prior.get('skipped', False),
                            'state': 'ready' if ready else 'queued', 'progress': 1 if ready else 0})
                    if not tracks:
                        raise ValueError('The playlist has no available tracks')
                    self.playlists[key].update(title=title, tracks=tracks)
                    self.selected = key
                    self.save(key)
                self.emit()
                for track in tracks:
                    if self.cancelled.is_set() or self.closing.is_set():
                        raise RuntimeError('Download cancelled')
                    if track['state'] == 'ready':
                        continue
                    with self.lock:
                        track.update(state='downloading', progress=0)
                    self.emit()
                    args = self.base_command() + ['--no-playlist', '--newline', '--progress', '--progress-delta', '.15',
                        '--progress-template', 'download:QS_PROGRESS:%(progress._percent_str)s',
                        '--print', 'after_move:QS_FILE:%(filepath)j', '--no-simulate', '--no-overwrites',
                        '--extract-audio', '--audio-format', 'opus', '--audio-quality', '0',
                        '--write-thumbnail', '--convert-thumbnails', 'jpg', '--write-info-json', '--embed-metadata',
                        '--ffmpeg-location', self.ffmpeg, '-o', str(folder / (track['id'] + '.%(ext)s')),
                        '--', 'https://www.youtube.com/watch?v=' + track['id']]
                    process = self.spawn(args)
                    last_error = '''
                    for line in process.stdout:
                        line = line.strip()
                        if line.startswith('QS_PROGRESS:'):
                            match = re.search(r'([\d.]+)%', line)
                            if match:
                                with self.lock:
                                    track['progress'] = min(1, float(match[1]) / 100)
                                self.emit()
                        elif line.startswith('QS_FILE:'):
                            filename = Path(json.loads(line[len('QS_FILE:'):])).name
                            self.track_path(folder, filename)
                            with self.lock:
                                track['file'] = filename
                        elif line.startswith('ERROR:'):
                            last_error = line[6:].strip()[:180]
                    process.wait()
                    if self.cancelled.is_set():
                        raise RuntimeError('Download cancelled')
                    with self.lock:
                        ready = process.returncode == 0 and self.track_path(folder, track['file']).is_file()
                        track.update(state='ready' if ready else 'failed', progress=1 if ready else track['progress'])
                        if not ready:
                            track['error'] = last_error or 'Download failed'
                        local_art = folder / (track['id'] + '.jpg')
                        if local_art.is_file():
                            track['art'] = local_art.as_uri()
                        info = read_json(folder / (track['id'] + '.info.json'), {})
                        track['artist'] = info.get('artist') or info.get('uploader') or track['artist']
                        self.save(key)
                    self.emit()
            except Exception as error:
                terminate(self.download_process)
                with self.lock:
                    self.error = str(error)[:180]
            finally:
                with self.lock:
                    self.busy = False
                    self.download_process = None
                    if key and key in self.playlists:
                        for track in self.playlists[key]['tracks']:
                            if track.get('state') == 'downloading':
                                track['state'] = 'queued'
                        try:
                            self.save(key)
                        except OSError as error:
                            self.error = str(error)[:180]
                self.emit()

        def command(self, message):
            action = message.get('action')
            if action == 'scan':
                if not self.busy:
                    self.scan()
                self.emit()
            elif action == 'select':
                self.select(message.get('id', '''))
            elif action == 'download':
                self.start_download(message.get('url', '''))
            elif action == 'update':
                self.start_download(self.playlists.get(self.selected, {}).get('source', '''))
            elif action == 'cancel':
                self.cancelled.set()
                terminate(self.download_process)
            elif action == 'play':
                self.play(message.get('id', '''))
            elif action == 'toggle':
                if self.current.get('loaded'):
                    self.player.set_paused(not self.player.pause_requested)
                else:
                    self.play()
            elif action == 'seek':
                position = message.get('position')
                if not isinstance(position, (int, float)) or isinstance(position, bool) or not math.isfinite(position):
                    raise ValueError('Invalid playback position')
                with self.lock:
                    duration = self.current.get('duration', 0)
                    if not self.current.get('loaded') or duration <= 0:
                        return
                    target = max(0, min(duration, position))
                self.player.send(['seek', target, 'absolute+exact'])
            elif action == 'next':
                self.next_track(1)
            elif action == 'previous':
                self.next_track(-1)
            elif action == 'skip':
                self.skip(message.get('id', '''))
            elif action == 'delete':
                self.delete()
            else:
                raise ValueError('Unknown media command')

        def close(self):
            self.closing.set()
            self.cancelled.set()
            terminate(self.download_process)
            self.player.close()


    def main():
        parser = argparse.ArgumentParser()
        parser.add_argument('--root', default=str(Path.home() / 'Music/Playlists'))
        for name in ['yt-dlp', 'ffmpeg', 'mpv', 'node']:
            parser.add_argument('--' + name, default=name)
        args = parser.parse_args()
        write_lock = threading.Lock()
        def emit(value):
            with write_lock:
                try:
                    print(json.dumps(value, ensure_ascii=False), flush=True)
                except BrokenPipeError:
                    pass
        try:
            library = Library(args.root, emit, args.yt_dlp, args.ffmpeg, args.mpv, args.node)
        except OSError as error:
            emit({'playlists': [], 'tracks': [], 'selected': ''', 'title': ''', 'source': ''',
                  'current': {}, 'busy': False, 'error': str(error)[:180]})
            return
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
        try:
            library.emit()
            for line in sys.stdin:
                try:
                    library.command(json.loads(line))
                except Exception as error:
                    library.error = str(error)[:180]
                    library.emit()
        finally:
            library.close()


    if __name__ == '__main__':
        main()
  '';

  mediaServiceQml = pkgs.writeText "MediaService.qml" ''
    import QtQuick
    import Quickshell
    import Quickshell.Io
    import Quickshell.Services.Mpris

    Scope {
        id: media
        property bool active: false
        property bool started: false
        property string mode: "normal"
        property var state: ({playlists: [], tracks: [], selected: "", title: "", source: "", current: {}, busy: false, error: ""})
        readonly property alias tracksModel: trackRows
        readonly property alias playlistsModel: playlistRows
        ListModel { id: trackRows }
        ListModel { id: playlistRows }
        function syncRows(model, rows) {
            if(model.count === rows.length && rows.every((row,i) => model.get(i).key === row.id))
                return;
            model.clear();
            rows.forEach(row => model.append({key:row.id}));
        }
        onStateChanged: { syncRows(trackRows,state.tracks); syncRows(playlistRows,state.playlists); }
        property var externalPlayer: Mpris.players.values.find(player => player.isPlaying)
            ?? Mpris.players.values.find(player => player.canControl) ?? null
        readonly property bool local: !!state.current.loaded && (!!state.current.playing || !externalPlayer?.isPlaying)
        readonly property var preview: state.tracks.find(track => track.state === "ready" && !track.skipped) ?? state.tracks[0] ?? null
        readonly property string title: local ? state.current.title ?? "" : externalPlayer?.trackTitle || preview?.title || ""
        readonly property string artist: local ? state.current.artist ?? "" : externalPlayer?.trackArtist || preview?.artist || ""
        readonly property string artwork: local ? state.current.art ?? "" : externalPlayer?.trackArtUrl || preview?.art || ""
        readonly property bool playing: local ? !!state.current.playing : !!externalPlayer?.isPlaying
        readonly property bool canToggle: local || !!externalPlayer?.canTogglePlaying || !!preview && preview.state === "ready" && !preview.skipped
        readonly property bool canPrevious: local || !!externalPlayer?.canGoPrevious
        readonly property bool canNext: local || !!externalPlayer?.canGoNext

        readonly property real duration: Math.max(0, Number(local ? state.current.duration ?? 0 : externalPlayer?.lengthSupported ? externalPlayer.length : 0) || 0)
        readonly property real position: Math.max(0, Math.min(duration, Number(local ? state.current.position ?? 0 : externalPlayer?.positionSupported ? externalPlayer.position : 0) || 0))
        readonly property bool canSeek: duration > 0 && (local || !!externalPlayer?.canSeek && !!externalPlayer?.positionSupported)
        // MPRIS positions advance when read, rather than emitting continuous updates.
        Timer {
            interval: 250; repeat: true
            running: media.active && !media.local && media.playing && !!media.externalPlayer?.positionSupported
            onTriggered: media.externalPlayer.positionChanged()
        }
        function seek(seconds) {
            if (!canSeek || !Number.isFinite(seconds)) return;
            const target = Math.max(0, Math.min(duration, seconds));
            if (local) send("seek", {position: target});
            else externalPlayer.position = target;
        }

        function send(action, values) {
            if (!backend.running)
                return;
            backend.write(JSON.stringify(Object.assign({action: action}, values ?? {})) + "\n");
        }
        function acceptState(line) {
            try {
                const next = JSON.parse(line);
                if (Array.isArray(next.playlists) && Array.isArray(next.tracks) && next.current)
                    state = next;
            } catch (error) { /* Ignore an incomplete frame; the next state repairs it. */ }
        }
        function playTrack(id) {
            if (externalPlayer?.isPlaying)
                externalPlayer.pause();
            send("play", {id: id});
        }
        function toggle() {
            if (local)
                send("toggle");
            else if (externalPlayer?.canTogglePlaying)
                externalPlayer.togglePlaying();
            else
                playTrack(preview?.id ?? "");
        }
        function previous() { if (local) send("previous"); else externalPlayer?.previous(); }
        function next() { if (local) send("next"); else externalPlayer?.next(); }
        function download(url) { mode = "normal"; send("download", {url: url}); }
        function choose(id) { send("select", {id: id}); mode = "normal"; }
        function dismissEditor() { mode = "normal"; }

        onActiveChanged: {
            if (active) {
                started = true;
                send("scan");
            } else {
                mode = "normal";
            }
        }
        Process {
            id: backend
            running: media.started
            command: ["${pkgs.python3}/bin/python3", Quickshell.shellPath("PlaylistBackend.py"),
                "--yt-dlp", "${pkgs.yt-dlp}/bin/yt-dlp", "--ffmpeg", "${pkgs.ffmpeg}/bin",
                "--mpv", "${pkgs.mpv}/bin/mpv", "--node", "${pkgs.nodejs}/bin/node"]
            stdinEnabled: true
            onStarted: media.send("scan")
            stdout: SplitParser { onRead: data => media.acceptState(data) }
            onExited: {
                media.started = false;
                media.state = Object.assign({}, media.state, {busy: false, error: media.state.error || "Music service stopped", current: {}});
            }
        }
    }
  '';

  frostedSurfaceQml = pkgs.writeText "FrostedSurface.qml" ''
    import QtQuick
    import Quickshell.Widgets

    ClippingRectangle {
        id: surface
        property QtObject glass: null
        property color tint: "#bf151515"
        property Gradient tintGradient: null
        readonly property rect sampleRect: {
            if (!glass || !glass.root) return Qt.rect(0, 0, width, height);
            // Track layout/scroll animation properties before mapping nested controls.
            const revision = glass.revision;
            const p = mapToItem(glass.root, 0, 0);
            const q = mapToItem(glass.root, width, height);
            return Qt.rect(glass.origin.x + p.x * glass.scale,
                glass.origin.y + p.y * glass.scale,
                (q.x-p.x) * glass.scale, (q.y-p.y) * glass.scale);
        }
        color: "transparent"
        ShaderEffectSource {
            anchors.fill: parent
            sourceItem: surface.glass?.source ?? null
            sourceRect: surface.sampleRect
            live: sourceItem !== null && surface.visible
            visible: sourceItem !== null
        }
        Rectangle {anchors.fill:parent;color:surface.tint;gradient:surface.tintGradient}
    }
  '';

  playlistScrollBarQml = pkgs.writeText "PlaylistScrollBar.qml" ''
    import QtQuick
    import QtQuick.Controls

    ScrollBar {
        id: bar
        implicitWidth: 6
        padding: 0
        minimumSize: 0.08
        policy: ScrollBar.AsNeeded
        visible: size < 1
        hoverEnabled: true
        background: Item {}
        contentItem: Rectangle {
            implicitWidth: 4;implicitHeight: 20
            radius: width/2
            color: "white"
            opacity: bar.pressed || bar.hovered ? 0.9 : 0.4
        }
        HoverHandler {cursorShape: bar.vertical ? Qt.SizeVerCursor : Qt.SizeHorCursor}
    }
  '';

  mediaButtonQml = pkgs.writeText "MediaButton.qml" ''
    import QtQuick
    import QtQuick.Controls

    AbstractButton {
        id: button
        property QtObject glass: null
        property string glyph: ""
        property string label: ""
        property bool motionEnabled: true
        property bool selected: false
        property real iconSize: 26
        padding: 0
        hoverEnabled: true
        Accessible.name: label
        implicitWidth: 56
        implicitHeight: 42
        background: FrostedSurface {
            id: buttonSurface
            radius: Math.min(width, height) / 2
            glass: button.glass
            tint: button.selected ? "#bf303030" : "#bf222222"
            HoverOutline {
                anchors.fill: parent
                cornerRadius: buttonSurface.radius
                hovered: button.hovered || button.visualFocus
                active: button.enabled
                motionEnabled: button.motionEnabled
            }
        }
        contentItem: Text {
            text: button.glyph
            color: "white"
            opacity: button.enabled ? 1 : 0.3
            font.family: "0xProto Nerd Font Mono"
            font.pixelSize: button.iconSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        HoverHandler { cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }
  '';

  waveVolumeQml = pkgs.writeText "WaveVolume.qml" ''
    import QtQuick
    import QtQuick.Controls

    Item {
        id: volume
        required property var audio
        property bool motionEnabled: true
        property string accessibleLabel: "System volume"
        implicitHeight: 42
        Slider {
            id: slider
            objectName: "mediaVolume"
            width: parent.width - 46
            height: parent.height
            from: 0; to: 1; stepSize: 0.01
            value: volume.audio.volume
            enabled: volume.audio.available
            Accessible.name: volume.accessibleLabel
            onMoved: volume.audio.setVolume(value)
            background: Canvas {
                id: wave
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d"); ctx.reset();
                    const count = Math.max(16, Math.floor((width-12)/8));
                    ctx.lineWidth = 1.5; ctx.lineCap = "round";
                    for (let i = 0; i < count; ++i) {
                        const t = i/(count-1), x = 6+t*(width-12);
                        const bands = volume.audio.bands;
                        const index = Math.min(bands.length-1, Math.floor(t*bands.length));
                        const level = volume.motionEnabled && !volume.audio.muted ? bands[index] || 0 : 0;
                        const extent = Math.max(0.01, level*12);
                        ctx.strokeStyle = !volume.audio.muted && t <= slider.value ? "white" : "#626262";
                        ctx.beginPath();ctx.moveTo(x,height/2-extent);ctx.lineTo(x,height/2+extent);ctx.stroke();
                    }
                }
                onWidthChanged: requestPaint()
                Connections {
                    target: volume.audio
                    function onBandsChanged() { wave.requestPaint(); }
                    function onMutedChanged() { wave.requestPaint(); }
                }
                Connections { target: slider; function onValueChanged() { wave.requestPaint(); } }
                Component.onCompleted: requestPaint()
            }
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * slider.availableWidth - width/2
                y: (slider.height-height)/2
                width: 3; height: 28; radius: 1.5
                color: "white"
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: slider.enabled ? Qt.SizeHorCursor : Qt.ArrowCursor
                hoverEnabled: true
                onWheel: event => { volume.audio.scroll(event.angleDelta.y); event.accepted = true; }
            }
        }
        Text {
            x: parent.width-width; anchors.verticalCenter: parent.verticalCenter
            text: volume.audio.available ? Math.round(volume.audio.volume*100) + "%" : "—"
            color: "white";font.family: "0xProto Nerd Font Mono";font.pixelSize: 11
        }
    }
  '';

  mediaTrackRowQml = pkgs.writeText "MediaTrackRow.qml" ''
    import QtQuick
    import QtQuick.Controls
    import QtQuick.Effects
    import Quickshell.Widgets

    AbstractButton {
        id: row
        property QtObject glass: null
        required property var track
        property bool current: false
        property bool modify: false
        property bool motionEnabled: true
        readonly property bool exclusionHovered: modify && (hovered || visualFocus)
        property real exclusionReveal: exclusionHovered ? 1 : 0
        Behavior on exclusionReveal { NumberAnimation {duration: row.motionEnabled ? 150 : 0;easing.type:Easing.OutCubic} }
        padding: 0
        hoverEnabled: true
        implicitHeight: 68
        Accessible.name: (modify ? (track.skipped ? "Include " : "Exclude ") : "Play ") + track.title
        background: FrostedSurface {
            radius: 15.5
            glass: row.glass
            tint: row.current ? "#bf292929" : "#bf191919"
            HoverOutline { anchors.fill: parent;cornerRadius: 15.5;hovered: row.hovered || row.visualFocus;motionEnabled: row.motionEnabled }
        }
        contentItem: Item {
            Item {
                anchors.fill: parent
                opacity: (row.track.skipped ? 0.38 : 1) * (1 - row.exclusionReveal * 0.6)
                layer.enabled: row.exclusionReveal > 0
                layer.effect: MultiEffect {blurEnabled: true;blurMax: 12;blur: row.exclusionReveal}
                ClippingRectangle {
                    x: 9;y: (parent.height-height)/2;width: 64;height: 46;radius: 9;color: "#30151515"
                    Image { anchors.fill: parent;source: row.track.art ?? "";fillMode: Image.PreserveAspectCrop;asynchronous: true }
                    Text {anchors.centerIn:parent;visible: !row.track.art;text:"";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:18}
                }
                Text {
                    x: 83;anchors.verticalCenter: parent.verticalCenter;width: Math.max(0,parent.width-161);height: 20
                    text: row.track.title;color: "white";font.family: "0xProto Nerd Font Mono";font.pixelSize: 11
                    font.strikeout: !!row.track.skipped;elide: Text.ElideRight;verticalAlignment:Text.AlignVCenter
                }
                Text {
                    x: parent.width-70;anchors.verticalCenter:parent.verticalCenter;width:60;height:20
                    text: row.modify ? row.track.artist??"" : row.track.state === "downloading" ? Math.round(row.track.progress*100)+"%"
                        : row.track.state === "queued" ? "󰔟" : row.track.state === "failed" ? "" : row.track.artist ?? ""
                    color: "#bbbbbb"
                    font.family: "0xProto Nerd Font Mono";font.pixelSize: 9
                    horizontalAlignment: Text.AlignRight;verticalAlignment:Text.AlignVCenter;elide: Text.ElideRight
                }
            }
            Text {
                anchors.centerIn:parent
                text:row.track.skipped?"Include in playing":"Exclude from playing"
                color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:12
                opacity:row.exclusionReveal
            }
            Rectangle {
                x:9;y:parent.height-5;height:2;radius:1
                width:(parent.width-18)*Math.max(0,Math.min(1,row.track.progress??0))
                color:"white";visible:row.track.state==="downloading"
            }
        }
        HoverHandler {cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor}
    }
  '';

  mediaMorphPanelQml = pkgs.writeText "MediaMorphPanel.qml" ''
    import QtQuick

    FrostedSurface {
        id: panel
        property bool opened: false
        property bool motionEnabled: true
        property real originX: 0
        property real compactWidth: 88
        property real fullWidth: 288
        property real fullHeight: 380
        property real progress: 0
        x: originX*(1-progress)
        width: compactWidth+(fullWidth-compactWidth)*progress
        height: 38+(fullHeight-38)*progress
        radius: 19+5*progress
        tint: "#bf151515"
        clip: true
        visible: progress>0
        function retarget() {
            travel.stop();
            const target=opened?1:0;
            if(!motionEnabled){progress=target;return;}
            travel.from=progress;travel.to=target;
            travel.duration=opened?360:280;
            travel.easing.type=opened?Easing.OutCubic:Easing.InCubic;
            travel.restart();
        }
        onOpenedChanged:retarget()
        onMotionEnabledChanged:retarget()
        NumberAnimation{id:travel;target:panel;property:"progress"}
    }
  '';

  mediaDetailsQml = pkgs.writeText "MediaDetails.qml" ''
    import QtQuick
    import QtQuick.Controls
    import Quickshell.Widgets

    FocusScope {
        id: details
        objectName: "mediaDetails"
        required property var media
        required property var audio
        property Item glassSource: null
        property point glassPosition: Qt.point(0, 0)
        property bool motionEnabled: true
        readonly property real columnWidth: 252
        readonly property real rightWidth: 288
        readonly property real panelHeight: 380
        width: 600; height: 420
        QtObject {
            id: glassContext
            property Item source: details.glassSource
            property Item root: details
            property point origin: details.glassPosition
            property real scale: details.scale
            // Invalidate crop coordinates when panels morph, the widget moves, or rows scroll.
            property int revision: 0
            onLayoutChanged: Qt.callLater(() => { revision++; })
            property var layout: [origin.x, origin.y, scale, details.width, details.height,
                downloadPanel.progress, choosePanel.progress, modifyPanel.progress,
                tracks.contentY, playlists.contentY, editableTracks.contentY]
        }
        function dismissAt(x, y) {
            const panel = media.mode === "download" ? downloadPanel
                : media.mode === "choose" ? choosePanel : media.mode === "modify" ? modifyPanel : null;
            if (!panel) return;
            const p = panel.mapFromItem(details, x, y);
            if (p.x < 0 || p.y < 0 || p.x > panel.width || p.y > panel.height)
                media.dismissEditor();
        }
        TapHandler {
            onPressedChanged: if (pressed) details.dismissAt(point.position.x, point.position.y)
        }

        Item {
            x:20;y:20;width:details.columnWidth;height:details.panelHeight
            ClippingRectangle {
                id: banner
                width:parent.width;height:164;radius:16;color:"#40151515"
                Image {anchors.fill:parent;source:details.media.artwork;fillMode:Image.PreserveAspectCrop;asynchronous:true}
                Text {anchors.centerIn:parent;visible:!details.media.artwork;text:"";color:"#777777";font.family:"0xProto Nerd Font Mono";font.pixelSize:44}
                Rectangle {
                    anchors.fill:parent
                    gradient:Gradient {
                        GradientStop{position:0.45;color:"transparent"}
                        GradientStop{position:1;color:"#d9151515"}
                    }
                }
            }
            Text {
                x:10;y:banner.height-16;width:parent.width-20;height:64
                text:details.media.title||"No media"
                color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:20
                font.weight:Font.DemiBold
                wrapMode:Text.Wrap;maximumLineCount:2;elide:Text.ElideRight
            }
            Row {
                x:(parent.width-width)/2;y:224;spacing:12
                MediaButton {glass:glassContext;objectName:"previousMedia";glyph:"";label:"Previous";enabled:details.media.canPrevious;motionEnabled:details.motionEnabled;onClicked:details.media.previous()}
                MediaButton {glass:glassContext;objectName:"toggleMedia";width:64;iconSize:30;glyph:details.media.playing?"":"";label:details.media.playing?"Pause":"Play";enabled:details.media.canToggle;motionEnabled:details.motionEnabled;onClicked:details.media.toggle()}
                MediaButton {glass:glassContext;objectName:"nextMedia";glyph:"";label:"Next";enabled:details.media.canNext;motionEnabled:details.motionEnabled;onClicked:details.media.next()}
            }
            Item {
                y:276;width:parent.width;height:42
                function timestamp(value) {
                    const seconds=Math.max(0,Math.floor(value));
                    return Math.floor(seconds/60)+":"+String(seconds%60).padStart(2,"0");
                }
                Slider {
                    id:seek;objectName:"mediaSeek"
                    width:parent.width;height:24;padding:6
                    from:0;to:Math.max(1,details.media.duration);value:details.media.position
                    enabled:details.media.canSeek
                    Accessible.name:"Playback position"
                    Accessible.description:parent.timestamp(value)+" / "+parent.timestamp(details.media.duration)
                    onMoved:details.media.seek(value)
                    background:Rectangle {
                        x:seek.leftPadding;y:(seek.height-height)/2
                        width:seek.availableWidth;height:3;radius:1.5;color:"#626262"
                        Rectangle {width:parent.width*seek.visualPosition;height:parent.height;radius:1.5;color:"white";opacity:seek.enabled?1:0.35}
                    }
                    handle:Rectangle {
                        x:seek.leftPadding+seek.visualPosition*(seek.availableWidth-width)
                        y:(seek.height-height)/2;width:8;height:8;radius:4;color:"white"
                        visible:seek.enabled
                    }
                    HoverHandler {cursorShape:seek.enabled?Qt.SizeHorCursor:Qt.ArrowCursor}
                }
                Text {x:6;y:26;text:parent.timestamp(details.media.position);color:"#bbbbbb";font.family:"0xProto Nerd Font Mono";font.pixelSize:9}
                Text {anchors.right:parent.right;anchors.rightMargin:6;y:26;text:parent.timestamp(details.media.duration);color:"#bbbbbb";font.family:"0xProto Nerd Font Mono";font.pixelSize:9}
            }
            WaveVolume {y:332;width:parent.width;audio:details.audio;motionEnabled:details.motionEnabled}
        }

        Rectangle {x:281;y:28;width:1;height:364;color:"#16ffffff"}

        Item {
            id:right
            x:292;y:20;width:details.rightWidth;height:details.panelHeight
            Row {
                spacing:8
                opacity:1-Math.max(downloadPanel.progress,choosePanel.progress,modifyPanel.progress)
                enabled:details.media.mode==="normal"
                MediaButton {glass:glassContext;
                    objectName:"downloadPlaylist";width:88;height:38;glyph:details.media.state.busy?"":""
                    label:details.media.state.busy?"Cancel download":"Download playlist"
                    motionEnabled:details.motionEnabled
                    onClicked: {
                        if(details.media.state.busy)details.media.send("cancel");
                        else {details.media.mode="download";Qt.callLater(()=>playlistUrl.forceActiveFocus());}
                    }
                }
                MediaButton {glass:glassContext;objectName:"choosePlaylist";width:88;height:38;glyph:"";label:"Choose playlist";motionEnabled:details.motionEnabled;onClicked:{details.media.send("scan");details.media.mode="choose";}}
                MediaButton {glass:glassContext;objectName:"modifyPlaylist";width:88;height:38;glyph:"";label:"Modify playlist";enabled:details.media.state.selected!=="";motionEnabled:details.motionEnabled;onClicked:details.media.mode="modify"}
            }
            Text {
                x:8;y:63;width:parent.width-16;height:26
                text:details.media.state.title||(details.media.state.busy?"…":"")
                color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:13
                elide:Text.ElideRight
                opacity:1-Math.max(choosePanel.progress,modifyPanel.progress)
            }
            ListView {
                id:tracks;objectName:"mediaTracks"
                x:0;y:98;width:parent.width-14;height:parent.height-y-(errorText.visible?32:0)
                clip:true;spacing:4
                model:details.media.tracksModel
                opacity:1-Math.max(choosePanel.progress,modifyPanel.progress)
                enabled:details.media.mode==="normal"||details.media.mode==="download"
                delegate:MediaTrackRow {glass:glassContext;
                    required property int index
                    width:tracks.width;track:details.media.state.tracks[index]??({title:"",state:"queued"});motionEnabled:details.motionEnabled
                    current:details.media.state.current.playlist===details.media.state.selected&&details.media.state.current.track===track.id
                    enabled:track.state==="ready"&&!track.skipped
                    onClicked:details.media.playTrack(track.id)
                }
                ScrollBar.vertical:PlaylistScrollBar {
                            objectName:"tracksScrollBar"
                            parent:tracks.parent
                            anchors.top:tracks.top
                            anchors.bottom:tracks.bottom
                            anchors.left:tracks.right
                            anchors.leftMargin:6
                            opacity:tracks.opacity
                            enabled:tracks.enabled
                        }
            }
            Text {
                id:errorText
                x:8;y:parent.height-height;width:parent.width-16;height:30
                visible:details.media.state.error!==""
                text:details.media.state.error
                color:"#bbbbbb";font.family:"0xProto Nerd Font Mono";font.pixelSize:10
                wrapMode:Text.Wrap;maximumLineCount:2;elide:Text.ElideRight
            }

            MediaMorphPanel {glass:glassContext;
                id:downloadPanel
                z:3;originX:0;fullWidth:right.width;fullHeight:38
                opened:details.media.mode==="download";motionEnabled:details.motionEnabled
                TextField {
                    id:playlistUrl;objectName:"playlistUrl"
                    anchors.fill:parent;leftPadding:14;rightPadding:14
                    color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:11
                    placeholderText:"YouTube playlist";placeholderTextColor:"#888888"
                    selectByMouse:true
                    background:Item{}
                    opacity:downloadPanel.progress
                    enabled:downloadPanel.opened
                    onAccepted: {
                        const value=text.trim();
                        if(value!==""){details.media.download(value);text="";}
                    }
                }
                HoverOutline {anchors.fill:parent;cornerRadius:19;hovered:playlistUrl.activeFocus;active:downloadPanel.opened;motionEnabled:details.motionEnabled}
            }

            MediaMorphPanel {glass:glassContext;
                id:choosePanel
                z:2;originX:96;fullWidth:right.width;fullHeight:right.height
                opened:details.media.mode==="choose";motionEnabled:details.motionEnabled
                Item {
                    anchors.fill:parent;opacity:choosePanel.progress;enabled:choosePanel.opened
                    Text {width:parent.width;height:38;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter;text:"";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:20}
                    ListView {
                        id:playlists;objectName:"playlistChoices"
                        x:0;y:48;width:parent.width-14;height:parent.height-y-4;clip:true;spacing:4
                        model:details.media.playlistsModel
                        delegate:MediaTrackRow {glass:glassContext;
                            required property int index
                            readonly property var entry:details.media.state.playlists[index]??({})
                            width:playlists.width
                            track:({id:entry.id,title:entry.title??"",artist:entry.count+" ",art:entry.art,state:"ready"})
                            current:entry.id===details.media.state.selected
                            motionEnabled:details.motionEnabled
                            onClicked:details.media.choose(entry.id)
                        }
                        ScrollBar.vertical:PlaylistScrollBar {
                            objectName:"playlistsScrollBar"
                            parent:playlists.parent
                            anchors.top:playlists.top
                            anchors.bottom:playlists.bottom
                            anchors.left:playlists.right
                            anchors.leftMargin:6
                            opacity:playlists.opacity
                            enabled:playlists.enabled
                        }
                    }
                }
            }

            MediaMorphPanel {glass:glassContext;
                id:modifyPanel
                z:2;originX:192;fullWidth:right.width;fullHeight:right.height
                opened:details.media.mode==="modify";motionEnabled:details.motionEnabled
                Item {
                    anchors.fill:parent;opacity:modifyPanel.progress;enabled:modifyPanel.opened
                    Row {
                        x:0;y:0;spacing:8
                        MediaButton {glass:glassContext;width:88;height:38;glyph:"";label:"Move playlist to Trash";enabled:!details.media.state.busy;motionEnabled:details.motionEnabled;onClicked:{details.media.send("delete");details.media.mode="normal";}}
                        MediaButton {glass:glassContext;width:88;height:38;glyph:"";label:"Update playlist";enabled:!details.media.state.busy&&details.media.state.source!=="";motionEnabled:details.motionEnabled;onClicked:{details.media.send("update");details.media.mode="normal";}}
                        MediaButton {glass:glassContext;
                            width:88;height:38;glyph:"󰒭";label:"Exclude current track"
                            enabled:details.media.state.current.playlist===details.media.state.selected&&!!details.media.state.current.track
                            motionEnabled:details.motionEnabled
                            onClicked:details.media.send("skip",{id:details.media.state.current.track})
                        }
                    }
                    ListView {
                        id:editableTracks;objectName:"playlistModify"
                        x:0;y:48;width:parent.width-14;height:parent.height-y-4;clip:true;spacing:4
                        model:details.media.tracksModel
                        delegate:MediaTrackRow {glass:glassContext;
                            required property int index
                            width:editableTracks.width;track:details.media.state.tracks[index]??({title:"",state:"queued"});modify:true
                            motionEnabled:details.motionEnabled
                            current:details.media.state.current.playlist===details.media.state.selected&&details.media.state.current.track===track.id
                            onClicked:details.media.send("skip",{id:track.id})
                        }
                        ScrollBar.vertical:PlaylistScrollBar {
                            objectName:"editableTracksScrollBar"
                            parent:editableTracks.parent
                            anchors.top:editableTracks.top
                            anchors.bottom:editableTracks.bottom
                            anchors.left:editableTracks.right
                            anchors.leftMargin:6
                            opacity:editableTracks.opacity
                            enabled:editableTracks.enabled
                        }
                    }
                }
            }
        }
    }
  '';

  usageBackendPython = pkgs.writeText "UsageBackend.py" ''
    """Read-only system telemetry for Quickshell; one JSON frame per sample."""
    import argparse
    import csv
    import json
    import math
    from pathlib import Path
    import signal
    import subprocess
    import sys
    import threading
    import time


    def read(path):
        try:
            return path.read_text().strip()
        except (OSError, UnicodeError):
            return '''


    def number(value):
        try:
            result = float(value)
            return result if math.isfinite(result) else None
        except (TypeError, ValueError):
            return None


    def cpu_counters(text):
        result = {}
        for line in text.splitlines():
            fields = line.split()
            if not fields or not (fields[0] == 'cpu' or fields[0].startswith('cpu') and fields[0][3:].isdigit()):
                continue
            try:
                # guest/guest_nice are already included in user/nice. Do not add twice.
                values = [int(value) for value in fields[1:9]]
                if len(values) >= 4:
                    result[fields[0]] = (sum(values), values[3] + (values[4] if len(values) > 4 else 0))
            except ValueError:
                continue
        return result


    def cpu_percent(current, previous):
        if previous is None:
            return None
        total, idle = current[0] - previous[0], current[1] - previous[1]
        if total <= 0:
            return None
        return round(max(0, min(100, (total-max(0, idle))*100/total)), 2)


    def memory_info(text):
        values = {}
        for line in text.splitlines():
            fields = line.split()
            if len(fields) >= 2 and fields[1].isdigit():
                values[fields[0].rstrip(':')] = int(fields[1]) * 1024
        total = values.get('MemTotal', 0)
        if total <= 0:
            return {'used': None, 'total': None, 'percent': None}
        available = values.get('MemAvailable')
        if available is None:
            needed = ['MemFree', 'Buffers', 'Cached']
            if not all(key in values for key in needed):
                return {'used': None, 'total': total, 'percent': None}
            available = sum(values[key] for key in needed) + values.get('SReclaimable', 0) - values.get('Shmem', 0)
        used = max(0, min(total, total-available))
        return {'used': used, 'total': total, 'percent': used*100/total}


    def network_counters(text, interfaces):
        result = {}
        for line in text.splitlines():
            if ':' not in line:
                continue
            name, values = line.split(':', 1)
            name, fields = name.strip(), values.split()
            if name not in interfaces or len(fields) < 9:
                continue
            try:
                result[name] = (int(fields[0]), int(fields[8]))
            except ValueError:
                continue
        return result


    def network_rates(current, previous, elapsed):
        common = set(current) & set(previous)
        if not common or elapsed <= 0:
            return {'download': None, 'upload': None, 'interfaces': sorted(current)}
        return {'download': sum(max(0, current[key][0]-previous[key][0]) for key in common)/elapsed,
                'upload': sum(max(0, current[key][1]-previous[key][1]) for key in common)/elapsed,
                'interfaces': sorted(current)}


    def gpu_csv(text):
        try:
            fields = next(csv.reader(text.splitlines()))
            if len(fields) != 5:
                return {}
            usage, used, total, temperature = [number(v.strip()) for v in fields[1:]]
            return {'name': fields[0].strip(), 'percent': max(0, min(100, usage)) if usage is not None else None,
                    'used': used*1024**2 if used is not None and used >= 0 else None,
                    'total': total*1024**2 if total is not None and total > 0 else None,
                    'temperature': temperature}
        except (StopIteration, csv.Error):
            return {}


    class Collector:
        def __init__(self, proc='/proc', sysfs='/sys', nvidia_smi='/run/current-system/sw/bin/nvidia-smi'):
            self.proc, self.sysfs, self.nvidia_smi = Path(proc), Path(sysfs), nvidia_smi
            self.previous_cpu, self.previous_net, self.previous_time = {}, {}, None
            self.last_gpu, self.last_temperature = {}, None
            self.cpu_name = next((line.split(':', 1)[1].strip() for line in read(self.proc/'cpuinfo').splitlines()
                                  if line.startswith('model name') and ':' in line), ''')
            self.cpu_name = self.cpu_name.split('@')[0].replace('(R)', ''').replace('(TM)', ''').replace(' CPU', ''').strip()

        def temperature(self):
            packages, cores = [], []
            for hwmon in (self.sysfs/'class/hwmon').glob('hwmon*'):
                if read(hwmon/'name') not in {'coretemp', 'k10temp', 'zenpower'}:
                    continue
                for path in hwmon.glob('temp*_input'):
                    value = number(read(path))
                    if value is None or not -20000 <= value <= 150000:
                        continue
                    label = read(path.with_name(path.name.replace('_input', '_label'))).lower()
                    (packages if 'package' in label or label in {'tctl', 'tdie'} else cores).append(value/1000)
            return max(packages or cores, default=None)

        def interfaces(self):
            # Physical active uplinks avoid counting loopback, Docker and VPN traffic twice.
            return {path.name for path in (self.sysfs/'class/net').iterdir()
                    if (path/'device').exists() and read(path/'operstate') in {'up', 'unknown'}} if (self.sysfs/'class/net').exists() else set()

        def gpu(self):
            try:
                command = [self.nvidia_smi, '--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu',
                           '--format=csv,noheader,nounits', '--id=0']
                result = subprocess.run(command, capture_output=True, text=True, timeout=1, check=False)
                return gpu_csv(result.stdout) if result.returncode == 0 else {}
            except (OSError, subprocess.TimeoutExpired):
                return {}

        def sample(self, details=False, now=None):
            now = time.monotonic() if now is None else now
            cpus = cpu_counters(read(self.proc/'stat'))
            net = network_counters(read(self.proc/'net/dev'), self.interfaces())
            elapsed = now-self.previous_time if self.previous_time is not None else 0
            rates = network_rates(net, self.previous_net, elapsed)
            result = {'cpuName': self.cpu_name,
                      'cpu': cpu_percent(cpus['cpu'], self.previous_cpu.get('cpu')) if 'cpu' in cpus else None,
                      'cores': [{'id': int(key[3:]), 'percent': cpu_percent(cpus[key], self.previous_cpu.get(key))}
                                for key in sorted(cpus, key=lambda k: -1 if k == 'cpu' else int(k[3:])) if key != 'cpu'],
                      'ram': memory_info(read(self.proc/'meminfo')), 'network': rates}
            if details:
                self.last_temperature, self.last_gpu = self.temperature(), self.gpu()
            result.update(temperature=self.last_temperature, gpu=self.last_gpu)
            self.previous_cpu, self.previous_net, self.previous_time = cpus, net, now
            return result


    def main():
        parser = argparse.ArgumentParser()
        parser.add_argument('--nvidia-smi', default='/run/current-system/sw/bin/nvidia-smi')
        args = parser.parse_args()
        collector, stop, details = Collector(nvidia_smi=args.nvidia_smi), threading.Event(), threading.Event()
        def controls():
            for line in sys.stdin:
                try:
                    if json.loads(line).get('details') is True: details.set()
                    else: details.clear()
                except (ValueError, AttributeError):
                    continue
            stop.set()
        def halt(*_): stop.set()
        signal.signal(signal.SIGTERM, halt)
        signal.signal(signal.SIGINT, halt)
        threading.Thread(target=controls, daemon=True).start()
        first = True
        try:
            while not stop.is_set():
                started = time.monotonic()
                print(json.dumps(collector.sample(details.is_set()), allow_nan=False), flush=True)
                stop.wait(max(.05, (.25 if first else 1) - (time.monotonic()-started)))
                first = False
        except BrokenPipeError:
            pass


    if __name__ == '__main__':
        main()
  '';

  usageServiceQml = pkgs.writeText "UsageService.qml" ''
    import QtQuick
    import Quickshell
    import Quickshell.Io

    Scope {
        id: service
        property bool active: false
        property bool expanded: false
        property bool requested: false
        property var state: ({cpu:null,cores:[],cpuName:"",temperature:null,ram:{},gpu:{},network:{}})
        readonly property alias coresModel: coreRows
        ListModel {id:coreRows}
        function acceptState(line) {
            try {
                const next=JSON.parse(line);
                if (!Array.isArray(next.cores) || !next.ram || !next.gpu || !next.network) return;
                state=next;
                if(coreRows.count!==next.cores.length || next.cores.some((core,i)=>coreRows.get(i).key!==core.id)) {
                    coreRows.clear();next.cores.forEach(core=>coreRows.append({key:core.id}));
                }
            } catch(error) { /* Keep the last complete telemetry frame. */ }
        }
        function syncDetails() {if(collector.running)collector.write(JSON.stringify({details:expanded})+"\n");}
        onActiveChanged: {retry.stop();requested=active;}
        onExpandedChanged: syncDetails()
        Process {
            id:collector
            running:service.requested
            stdinEnabled:true
            command:["${pkgs.python3}/bin/python3",Quickshell.shellPath("UsageBackend.py")]
            onStarted:service.syncDetails()
            stdout:SplitParser {onRead:data=>service.acceptState(data)}
            onExited:{service.requested=false;if(service.active)retry.restart();}
        }
        Timer {id:retry;interval:2000;onTriggered:if(service.active)service.requested=true}
    }
  '';

  usageOutlineQml = pkgs.writeText "UsageOutline.qml" ''
    import QtQuick

    HoverOutline {
        id:outline
        property real cpu:0
        property real ram:0
        property real cpuLevel:Math.max(0,Math.min(1,cpu/100))
        property real ramLevel:Math.max(0,Math.min(1,ram/100))
        property color cpuColor:"#ead178"
        property color ramColor:"#9acb92"
        property real segmentGap:3
        pathVisible:false
        readonly property real straightLength:Math.max(0,innerWidth-2*radius)
        // Account for both round caps so the visible separation stays three pixels.
        readonly property real segmentMargin:segmentGap+strokeWidth
        readonly property real usableStraight:Math.max(0,straightLength-2*segmentMargin)
        readonly property real revealedStraight:Math.max(0,Math.min(straightLength,progress*halfLength-(innerHeight/2-radius+Math.PI*radius/2)))
        readonly property real cpuLength:Math.min(Math.max(0,revealedStraight-segmentMargin),usableStraight*cpuLevel)
        readonly property real ramLength:Math.min(Math.max(0,revealedStraight-segmentMargin),usableStraight*ramLevel)
        Behavior on cpuLevel {NumberAnimation{duration:outline.motionEnabled?280:0;easing.type:Easing.OutCubic}}
        Behavior on ramLevel {NumberAnimation{duration:outline.motionEnabled?280:0;easing.type:Easing.OutCubic}}
        Canvas {
            id:ink;anchors.fill:parent
            visible:outline.progress>0
            onPaint: {
                const ctx=getContext("2d");ctx.reset();
                const i=outline.edgeInset,r=outline.radius,w=outline.width,h=outline.height;
                const left=i+r,right=w-i-r;
                ctx.lineWidth=outline.strokeWidth;ctx.lineCap="round";ctx.lineJoin="round";
                // Each branch starts at the leftmost point, just like HoverOutline.
                function branch(top) {
                    let remaining=outline.progress*outline.halfLength;
                    ctx.strokeStyle="white";ctx.beginPath();ctx.moveTo(i,h/2);
                    const vertical=Math.max(0,outline.innerHeight/2-r),quarter=Math.PI*r/2;
                    function line(x1,y1,x2,y2,length) {
                        const amount=Math.min(remaining,length);remaining-=amount;
                        if(length>0)ctx.lineTo(x1+(x2-x1)*amount/length,y1+(y2-y1)*amount/length);
                    }
                    line(i,h/2,i,top?i+r:h-i-r,vertical);
                    if(remaining>0&&r>0) {
                        const amount=Math.min(remaining,quarter);remaining-=amount;
                        ctx.arc(left,top?i+r:h-i-r,r,Math.PI,top?Math.PI+amount/r:Math.PI-amount/r,!top);
                    }
                    if(remaining>0) {
                        const y=top?i:h-i;
                        const revealed=Math.min(remaining,outline.straightLength);
                        remaining-=revealed;
                        const level=top?outline.cpuLevel:outline.ramLevel;
                        if(level>0&&outline.usableStraight>0) {
                            ctx.stroke();
                            const start=outline.segmentMargin;
                            const length=top?outline.cpuLength:outline.ramLength;
                            if(length>0) {
                                ctx.strokeStyle=top?outline.cpuColor:outline.ramColor;
                                ctx.beginPath();ctx.moveTo(left+start,y);
                                ctx.lineTo(left+start+length,y);ctx.stroke();
                            }
                            const whiteStart=start+outline.usableStraight*level+outline.segmentMargin;
                            ctx.strokeStyle="white";ctx.beginPath();
                            ctx.moveTo(left+Math.min(revealed,whiteStart),y);
                            if(revealed>whiteStart)ctx.lineTo(left+revealed,y);
                        } else ctx.lineTo(left+revealed,y);
                    }
                    if(remaining>0&&r>0) {
                        const amount=Math.min(remaining,quarter);remaining-=amount;
                        ctx.arc(right,top?i+r:h-i-r,r,top?-Math.PI/2:Math.PI/2,top?-Math.PI/2+amount/r:Math.PI/2-amount/r,!top);
                    }
                    if(remaining>0)line(w-i,top?i+r:h-i-r,w-i,h/2,vertical);
                    ctx.stroke();
                }
                branch(true);branch(false);
            }
        }
        onProgressChanged:ink.requestPaint()
        onCpuLevelChanged:ink.requestPaint()
        onRamLevelChanged:ink.requestPaint()
        onWidthChanged:ink.requestPaint()
        onHeightChanged:ink.requestPaint()
        onSegmentGapChanged:ink.requestPaint()
        onMotionEnabledChanged:ink.requestPaint()
    }
  '';

  usageValueQml = pkgs.writeText "UsageValue.qml" ''
    import QtQuick

    Item {
        id:value
        property string text:"—"
        property string unit:""
        property int slots:0
        property real fontSize:26
        property bool active:true
        property bool motionEnabled:true
        implicitWidth:number.implicitWidth+(unit!==""?unitLabel.implicitWidth+4:0)
        implicitHeight:number.implicitHeight
        RollingClock {
            id:number
            clockMode:false
            timeText:value.text.padStart(value.slots," ")
            fontSize:value.fontSize
            active:value.active
            motionEnabled:value.motionEnabled
            width:implicitWidth;height:implicitHeight
        }
        Text {
            id:unitLabel
            x:number.width+4
            anchors.bottom:number.bottom;anchors.bottomMargin:2
            text:value.unit;color:"#bbbbbb"
            font.family:"0xProto Nerd Font Mono";font.pixelSize:10
        }
    }
  '';

  usageDetailsQml = pkgs.writeText "UsageDetails.qml" ''
    import QtQuick
    import QtQuick.Controls

    Item {
        id:details
        required property var usage
        property Item glassSource:null
        property point glassPosition:Qt.point(0,0)
        property bool active:false
        property bool motionEnabled:true
        width:600;height:420
        function fixed(value,decimals) {return typeof value==="number"&&Number.isFinite(value)?value.toFixed(decimals):"—";}
        function gib(value) {return typeof value==="number"?fixed(value/1073741824,1):"—";}
        function rate(value) {
            if(typeof value!=="number"||!Number.isFinite(value))return {text:"—",unit:"KiB/s"};
            const units=["B/s","KiB/s","MiB/s","GiB/s"];
            let index=0;
            while(value>=1024&&index<3){value/=1024;index++;}
            return {text:value.toFixed(index===0?0:1),unit:units[index]};
        }
        QtObject {
            id:glassContext
            property Item source:details.glassSource
            property Item root:details
            property point origin:details.glassPosition
            property real scale:details.scale
            property int revision:0
            property var layout:[origin.x,origin.y,scale,details.width,details.height,cores.contentY]
            onLayoutChanged:Qt.callLater(()=>{revision++;})
        }
        Item {
            x:20;y:20;width:252;height:380
            Text {text:"";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:24}
            Text {x:34;y:6;text:"CPU";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:12}
            Text {y:36;width:parent.width;text:details.usage.state.cpuName;color:"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:10;elide:Text.ElideRight}
            Text {y:67;text:"Usage";color:"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
            UsageValue {
                objectName:"usageCpu"
                y:84;text:details.fixed(details.usage.state.cpu,0);unit:"%";fontSize:38;slots:3
                active:details.active;motionEnabled:details.motionEnabled
            }
            Text {x:146;y:67;text:"Temperature";color:"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
            UsageValue {
                objectName:"usageTemperature"
                x:146;y:94;text:details.fixed(details.usage.state.temperature,0);unit:"°C";fontSize:26;slots:3
                active:details.active;motionEnabled:details.motionEnabled
            }
            Rectangle {y:155;width:parent.width;height:1;color:"#16ffffff"}
            Text {y:177;text:"Cores";color:"#aaaaaa";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
            GridView {
                id:cores;objectName:"usageCores"
                y:202;width:parent.width-12;height:parent.height-y
                cellWidth:120;cellHeight:80;clip:true
                model:details.usage.coresModel
                delegate:Item {
                    id:coreCell
                    required property int index
                    readonly property var core:details.usage.state.cores[index]??({})
                    width:120;height:80
                    FrostedSurface {
                        x:0;y:0;width:110;height:68;radius:15.5
                        glass:glassContext;tint:"#bf191919"
                        Text {x:11;y:10;text:"Core "+((coreCell.core.id??0)+1);color:"#aaaaaa";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
                        UsageValue {
                            x:11;y:30;text:details.fixed(coreCell.core.percent,0);unit:"%";fontSize:20;slots:3
                            active:details.active;motionEnabled:details.motionEnabled
                        }
                    }
                }
                ScrollBar.vertical:PlaylistScrollBar {
                    parent:cores.parent
                    anchors.top:cores.top;anchors.bottom:cores.bottom;anchors.left:cores.right;anchors.leftMargin:6
                }
            }
        }
        Rectangle {x:281;y:28;width:1;height:364;color:"#16ffffff"}
        Item {
            x:292;y:20;width:288;height:380
            Text {text:"󰍛";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:24}
            Text {x:34;y:6;text:"RAM";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:12}
            UsageValue {
                objectName:"usageRam"
                y:39;text:details.gib(details.usage.state.ram.used);unit:"GiB";fontSize:28;slots:4
                active:details.active;motionEnabled:details.motionEnabled
            }
            UsageValue {
                x:207;y:45;text:details.fixed(details.usage.state.ram.percent,0);unit:"%";fontSize:22;slots:3
                active:details.active;motionEnabled:details.motionEnabled
            }
            Text {y:82;text:"/ "+details.gib(details.usage.state.ram.total)+" GiB";color:"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
            Rectangle {y:112;width:parent.width;height:1;color:"#16ffffff"}
            Text {y:135;text:"󰢮";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:24}
            Text {x:34;y:140;text:"GPU";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:12}
            Text {x:73;y:141;width:parent.width-x;text:(details.usage.state.gpu.name??"").replace("NVIDIA GeForce ","");color:"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:10;elide:Text.ElideRight}
            Text {y:177;text:"Usage";color:"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
            Text {x:126;y:177;text:"VRAM";color:"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
            UsageValue {
                objectName:"usageGpu"
                y:195;text:details.fixed(details.usage.state.gpu.percent,0);unit:"%";fontSize:28;slots:3
                active:details.active;motionEnabled:details.motionEnabled
            }
            UsageValue {
                objectName:"usageVram"
                x:126;y:195;text:details.gib(details.usage.state.gpu.used);unit:"GiB";fontSize:28;slots:4
                active:details.active;motionEnabled:details.motionEnabled
            }
            Text {x:126;y:236;text:"/ "+details.gib(details.usage.state.gpu.total)+" GiB";color:"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
            Rectangle {y:270;width:parent.width;height:1;color:"#16ffffff"}
            Text {y:292;text:"󰛳";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:24}
            Text {x:34;y:298;text:"Network";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:12}
            Text {x:104;y:299;width:parent.width-x;text:(details.usage.state.network.interfaces??[]).join(", ");color:"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:9;horizontalAlignment:Text.AlignRight;elide:Text.ElideRight}
            Text {y:341;text:"";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:16}
            UsageValue {
                objectName:"usageDownload"
                x:25;y:333;text:details.rate(details.usage.state.network.download).text;unit:details.rate(details.usage.state.network.download).unit;fontSize:21;slots:5
                active:details.active;motionEnabled:details.motionEnabled
            }
            Text {x:147;y:341;text:"";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:16}
            UsageValue {
                objectName:"usageUpload"
                x:172;y:333;text:details.rate(details.usage.state.network.upload).text;unit:details.rate(details.usage.state.network.upload).unit;fontSize:21;slots:5
                active:details.active;motionEnabled:details.motionEnabled
            }
        }
    }
  '';

  windowBackendPython = pkgs.writeText "WindowBackend.py" ''
    """Window lifetimes and read-only application process telemetry."""
    import configparser
    import json
    import os
    import re
    from pathlib import Path
    import signal
    import subprocess
    import sys
    import threading
    import time


    def read(path):
        try:
            return path.read_text().strip()
        except (OSError, UnicodeError):
            return '''


    def process_stat(text):
        try:
            # Names may contain spaces and closing parentheses.
            fields = text[text.rfind(')') + 2:].split()
            return {'parent': int(fields[1]), 'ticks': int(fields[11])+int(fields[12]),
                    'start': int(fields[19])}
        except (ValueError, IndexError):
            return None


    def gpu_processes(text):
        result = {}
        valid = False
        for line in text.splitlines():
            fields = line.split()
            if len(fields) < 5 or not fields[0].isdigit():
                continue
            valid = True
            if not fields[1].isdigit():
                continue
            pid = int(fields[1])
            try:
                value = float(fields[3])
                if not 0 <= value <= 100:
                    value = None
            except ValueError:
                value = None
            # Multiple devices/contexts must not overwrite one another.
            previous = result.get(pid, 0)
            result[pid] = None if previous is None or value is None else min(100, previous+value)
        return result if valid else None


    class IconResolver:
        def __init__(self, roots=None, theme=None):
            data = [Path(os.environ.get('XDG_DATA_HOME', str(Path.home()/'.local/share')))]
            data += [Path(p) for p in os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':') if p]
            self.roots = roots if roots is not None else [Path.home()/'.icons']+[p/'icons' for p in data]
            self.pixmaps = [p/'pixmaps' for p in data]
            config = configparser.ConfigParser()
            try:
                config.read(Path.home()/'.config/gtk-3.0/settings.ini')
            except configparser.Error:
                pass
            self.theme = theme or config.get('Settings', 'gtk-icon-theme-name', fallback='hicolor').strip('"')
            self.cache = {}

        def resolve(self, name):
            if not name:
                return '''
            if name in self.cache:
                return self.cache[name]
            candidate = Path(name)
            if candidate.is_absolute():
                result = candidate.as_uri() if candidate.is_file() else '''
            elif '/' in name or name in ('.', '..'):
                result = '''
            else:
                result = '''
                names = [name] if candidate.suffix in ('.svg','.png','.xpm') else [name+'.svg',name+'.png',name+'.xpm']
                for theme in dict.fromkeys([self.theme, 'hicolor']):
                    for root in self.roots:
                        base = root/theme
                        if not base.is_dir():
                            continue
                        matches = []
                        for filename in names:
                            matches += list(base.glob('*/apps/'+filename))+list(base.glob('apps/*/'+filename))
                        def quality(path):
                            return (0 if 'scalable' in path.parts else 1, -max([int(p.split('x')[0]) for p in path.parts if p.split('x')[0].isdigit()] or [0]))
                        matches.sort(key=quality)
                        found = next((p for p in matches if p.is_file()), None)
                        if found:
                            result = found.resolve().as_uri()
                            break
                    if result:
                        break
                if not result:
                    found = next((root/filename for root in self.pixmaps for filename in names if (root/filename).is_file()),None)
                    result = found.resolve().as_uri() if found else '''
            self.cache[name] = result
            return result


    class BrowserIcons:
        """Match per-window cached favicons without guessing between duplicate titles."""
        def __init__(self, root=None, proc=Path('/proc')):
            runtime = os.environ.get('XDG_RUNTIME_DIR')
            self.root = root if root is not None else Path(runtime)/'quickshell-chromium' if runtime else None
            self.proc = proc

        def live(self, pid, start):
            if not isinstance(pid,int) or pid<=0:
                return False
            stat=process_stat(read(self.proc/str(pid)/'stat'))
            return stat is not None and stat['start']==start

        @staticmethod
        def title(value):
            return re.sub(r'\s+-\s+(?:Chromium|Google Chrome)$',''',str(value)).strip()

        def resolve(self, windows):
            if self.root is None:
                return {}
            records=[]
            for path in list(self.root.glob('host-*/state.json'))[:64]:
                try:
                    if path.stat().st_size>1024*1024:
                        continue
                    state=json.loads(path.read_text())
                    if state.get('version')!=1 or not self.live(state.get('hostPid'),state.get('hostStart')) or not self.live(state.get('browserPid'),state.get('browserStart')):
                        continue
                    for row in state.get('windows',[])[:32]:
                        if isinstance(row,dict):
                            records.append((state['browserPid'],path.parent,row))
                except (OSError,ValueError,TypeError,AttributeError):
                    continue
            result={}
            for window in windows:
                if window.get('className',''').lower() not in ('chromium','chromium-browser','google-chrome','google-chrome-stable'):
                    continue
                title=self.title(window.get('title','''))
                matches=[(directory,row) for pid,directory,row in records
                         if pid==window.get('pid') and title and self.title(row.get('title','''))==title]
                if len(matches)>1:
                    def distance(match):
                        row=match[1]
                        return sum(abs(row.get(key,0)-window.get(key,0)) for key in ('left','top','width','height')
                                   if isinstance(row.get(key,0),(int,float)) and isinstance(window.get(key,0),(int,float)))
                    matches.sort(key=distance)
                    if distance(matches[1])-distance(matches[0])<8:
                        continue
                if not matches:
                    continue
                directory,row=matches[0]
                name=row.get('icon',''')
                if not isinstance(name,str) or not re.fullmatch(r'[a-f0-9]{64}\.(?:png|svg)',name):
                    continue
                icon=directory/name
                if icon.is_file():
                    result[window['key']]=icon.as_uri()
            return result


    class Collector:
        def __init__(self, proc=Path('/proc'), cpu_count=None, ticks=None, nvidia_smi='/run/current-system/sw/bin/nvidia-smi'):
            self.proc = proc
            self.cpu_count = cpu_count or os.cpu_count() or 1
            self.ticks = ticks or os.sysconf('SC_CLK_TCK')
            self.nvidia_smi = nvidia_smi
            self.previous = {}
            self.previous_time = None
            self.previous_key = None

        def processes(self):
            result = {}
            for path in self.proc.glob('[0-9]*/stat'):
                stat = process_stat(read(path))
                if stat:
                    result[int(path.parent.name)] = stat
            return result

        def gpu(self):
            try:
                output = subprocess.run([self.nvidia_smi, 'pmon', '-c', '1', '-s', 'u'],
                                        capture_output=True, text=True, timeout=1.5, check=True).stdout
                return gpu_processes(output)
            except (OSError, subprocess.SubprocessError):
                return None

        def sample(self, key, pid, now=None):
            now = time.monotonic() if now is None else now
            processes = self.processes()
            owned = {pid} if pid in processes else set()
            while True:
                children = {p for p, stat in processes.items() if stat['parent'] in owned}
                if children <= owned:
                    break
                owned |= children
            current = {(p, processes[p]['start']): processes[p]['ticks'] for p in owned}
            elapsed = now-self.previous_time if self.previous_time is not None else 0
            cpu = None
            if key == self.previous_key and elapsed > 0 and current and self.previous:
                delta = sum(max(0, value-self.previous[identity]) for identity, value in current.items() if identity in self.previous)
                cpu = round(min(100, delta*100/(elapsed*self.ticks*self.cpu_count)), 2)
            self.previous, self.previous_time, self.previous_key = current, now, key
            memory, known = 0, False
            for p in owned:
                lines = read(self.proc/str(p)/'smaps_rollup').splitlines()
                pss = next((line.split()[1] for line in lines if line.startswith('Pss:')), None)
                if pss and pss.isdigit():
                    memory += int(pss)*1024
                    known = True
                else:
                    # A restricted process may not expose PSS; RSS is the available fallback.
                    status = read(self.proc/str(p)/'status').splitlines()
                    rss = next((line.split()[1] for line in status if line.startswith('VmRSS:')), None)
                    if rss and rss.isdigit():
                        memory += int(rss)*1024
                        known = True
            total = next((line.split()[1] for line in read(self.proc/'meminfo').splitlines() if line.startswith('MemTotal:')), None)
            ram = round(memory*100/(int(total)*1024), 2) if known and total and total.isdigit() and int(total)>0 else None
            gpu_rows = self.gpu() if owned else None
            gpu = None
            if gpu_rows is not None:
                values = [gpu_rows[p] for p in owned if p in gpu_rows]
                if all(value is not None for value in values):
                    gpu = min(100, sum(values))
            return {'key':key, 'pids':sorted(owned), 'cpu':cpu, 'ram':ram, 'gpu':gpu}


    class Lifetimes:
        def __init__(self, path, session):
            self.path, self.session = path, session
            self.births = {}
            try:
                cached = json.loads(read(path))
                if cached.get('session') == session:
                    self.births = cached.get('births', {})
            except (ValueError, AttributeError):
                pass

        def update(self, windows, now=None):
            now = time.time()*1000 if now is None else now
            births = dict(self.births)
            for window in windows:
                key = str(window.get('key', '''))
                if key:
                    stamp = self.births.get(key, window.get('born', now))
                    births[key] = stamp if isinstance(stamp, (int,float)) and 0 < stamp <= now else now
            births = dict(list(births.items())[-512:])
            if births != self.births:
                self.births = births
                try:
                    self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                    temp = self.path.with_suffix('.tmp')
                    temp.write_text(json.dumps({'session':self.session, 'births':births}))
                    temp.chmod(0o600)
                    temp.replace(self.path)
                except OSError:
                    pass
            return self.births


    def main():
        cache = Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp'))/('quickshell-window-times-'+str(os.getuid())+'.json')
        lifetimes = Lifetimes(cache, os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '''))
        collector, icons, browser_icons = Collector(), IconResolver(), BrowserIcons()
        changed, stop, lock = threading.Event(), threading.Event(), threading.Lock()
        config = {'active':False, 'windows':[], 'key':''', 'pid':0}
        def controls():
            for line in sys.stdin:
                try:
                    value = json.loads(line)
                    if isinstance(value, dict) and isinstance(value.get('windows'), list):
                        with lock:
                            config.update(value)
                        changed.set()
                except (ValueError, AttributeError):
                    continue
            stop.set()
            changed.set()
        def halt(*_):
            stop.set()
            changed.set()
        signal.signal(signal.SIGTERM, halt)
        signal.signal(signal.SIGINT, halt)
        threading.Thread(target=controls, daemon=True).start()
        try:
            changed.wait()
            while not stop.is_set():
                changed.clear()
                with lock:
                    frame = dict(config)
                births = lifetimes.update(frame['windows'])
                state = collector.sample(frame['key'], frame['pid']) if frame['active'] and frame['pid']>0 else {'key':frame['key'], 'pids':[], 'cpu':None, 'ram':None, 'gpu':None}
                state['births'] = births
                state['icons'] = {w['key']:icons.resolve(w.get('icon', ''')) for w in frame['windows'] if w.get('key')}
                state['icons'].update(browser_icons.resolve(frame['windows']))
                print(json.dumps(state, allow_nan=False), flush=True)
                changed.wait(1 if frame['active'] else None)
        except BrokenPipeError:
            pass


    if __name__ == '__main__':
        main()
  '';

  windowServiceQml = pkgs.writeText "WindowService.qml" ''
    import QtQuick
    import Quickshell
    import Quickshell.Hyprland
    import Quickshell.Io

    Scope {
        id: service
        property bool active: false
        // Injectable inputs keep focus/close actions testable without touching real windows.
        property var clients: Hyprland.toplevels.values.map(t => t.lastIpcObject)
        property var ipcFocused: null
        property var focused: Hyprland.activeToplevel?.lastIpcObject ?? ipcFocused
        property int workspace: Hyprland.focusedWorkspace?.id ?? -1
        property var windows: []
        property var history: []
        property var births: ({})
        property var icons: ({})
        property string selectedAddress: ""
        property var state: ({key:"",pids:[],cpu:null,ram:null,gpu:null})
        property bool requested: true
        property string lastConfig: ""
        readonly property var current: windows.find(w => w.address === selectedAddress) ?? null
        readonly property bool desktop: current === null
        readonly property var recent: history.filter(address => address !== selectedAddress && windows.some(w => w.address === address)).slice(0,4)
            .map(address => windows.find(w => w.address === address))
        readonly property var pids: state.key === current?.key ? state.pids : []
        readonly property real born: current ? births[current.key] ?? current.born : 0
        signal dispatchRequested(string command)

        function addressValid(address) { return /^0x[0-9a-f]+$/i.test(address); }
        function iconFor(className) {
            const entry = DesktopEntries.heuristicLookup(className);
            return entry?.icon ?? "";
        }
        function refresh() {
            const now = Date.now(), old = windows;
            windows = clients.filter(c => c && addressValid(c.address)).map(c => {
                const key=String(c.stableId ?? c.address)+":"+String(c.pid);
                const prior = old.find(w => w.key === key);
                return {address:c.address,pid:c.pid || 0,key:key,
                    className:c.class || c.initialClass || "", title:c.title || c.class || "",
                    workspace:c.workspace?.id ?? -1,born:prior?.born ?? now,
                    left:c.at?.[0] ?? 0,top:c.at?.[1] ?? 0,width:c.size?.[0] ?? 0,height:c.size?.[1] ?? 0,
                    iconName:iconFor(c.class || c.initialClass || "")};
            });
            if (history.length===0 && windows.length>0)
                history=clients.filter(c=>addressValid(c.address)).slice()
                    .sort((a,b)=>(a.focusHistoryID??999)-(b.focusHistoryID??999)).map(c=>c.address);
            let next = windows.find(w => w.address === focused?.address && (workspace===-1 || w.workspace===workspace));
            if (!next && (!current || current.workspace!==workspace)) {
                // A layer taking focus on another monitor can clear activewindow.
                // Recover that workspace's most recently focused mapped window.
                const candidate=clients.filter(c=>c.workspace?.id===workspace && addressValid(c.address)).slice()
                    .sort((a,b)=>(a.focusHistoryID??999)-(b.focusHistoryID??999))[0];
                next=windows.find(w=>w.address===candidate?.address);
            }
            if (next) {
                selectedAddress = next.address;
                history = [next.address,...history.filter(a => a !== next.address)].slice(0,32);
            } else if (!current || current.workspace !== workspace) {
                // Layer-shell keyboard focus can temporarily clear activeToplevel.
                // Keep the last selected window only on its own workspace.
                selectedAddress = "";
            }
            history = history.filter(a => windows.some(w => w.address === a));
            sync();
        }
        function sync() {
            const config=JSON.stringify({active:active,key:current?.key ?? "",pid:current?.pid ?? 0,
                windows:windows.map(w => ({key:w.key,born:w.born,icon:w.iconName,pid:w.pid,className:w.className,
                    title:w.title,left:w.left,top:w.top,width:w.width,height:w.height}))});
            if (collector.running && config!==lastConfig) {collector.write(config+"\n");lastConfig=config;}
        }
        function acceptState(line) {
            try {
                const next = JSON.parse(line);
                if (!Array.isArray(next.pids) || !next.births) return;
                births = next.births;
                if(next.icons) icons=next.icons;
                state = next;
            } catch(error) { /* Keep the last complete frame. */ }
        }
        function focusWindow(address) {
            if (addressValid(address) && windows.some(w => w.address === address))
                dispatchRequested("focuswindow address:"+address);
        }
        function closeWindow() {
            if (current && addressValid(current.address))
                dispatchRequested("closewindow address:"+current.address);
        }
        onClientsChanged: Qt.callLater(refresh)
        onFocusedChanged: Qt.callLater(refresh)
        onWorkspaceChanged: Qt.callLater(refresh)
        onActiveChanged: sync()
        Connections {target:DesktopEntries.applications;function onValuesChanged(){Qt.callLater(service.refresh);}}
        Connections {
            target:Hyprland
            function onRawEvent(event) {
                if (["activewindowv2","workspacev2","openwindow","closewindow","movewindowv2"].includes(event.name))
                    Qt.callLater(() => {service.refresh();focusQuery.query();});
            }
        }
        Socket {
            id:focusQuery
            property string response:""
            path:Hyprland.requestSocketPath
            function query(){if(!connected)connected=true;}
            onConnectionStateChanged:if(connected){response="";write("j/activewindow");flush();queryTimeout.restart();}else queryTimeout.stop()
            parser:SplitParser {
                splitMarker:""
                onRead:data=>{
                    focusQuery.response+=data;
                    try {
                        const client=JSON.parse(focusQuery.response);
                        service.ipcFocused=client.address?client:null;
                        focusQuery.connected=false;
                        service.refresh();
                    }catch(error){/* Wait for a complete IPC reply. */}
                }
            }
        }
        Timer {id:queryTimeout;interval:500;onTriggered:focusQuery.connected=false}
        Component.onCompleted:Qt.callLater(()=>{refresh();focusQuery.query();})
        Process {
            id: collector
            running: service.requested
            stdinEnabled: true
            command: ["${pkgs.python3}/bin/python3",Quickshell.shellPath("WindowBackend.py")]
            onStarted: {service.lastConfig="";service.sync();}
            stdout: SplitParser {onRead: data => service.acceptState(data)}
            onExited: {service.requested=false;retry.restart();}
        }
        Timer {id:retry;interval:2000;onTriggered:service.requested=true}
    }
  '';

  windowAudioQml = pkgs.writeText "WindowAudio.qml" ''
    import QtQuick
    import Quickshell
    import Quickshell.Services.Pipewire

    Scope {
        id: audio
        required property var window
        required property var master
        property bool active: false
        property var candidates: Pipewire.nodes.values.filter(n => n.isStream && n.isSink)
        readonly property var matched: active && !window.desktop ? candidates.filter(matches) : []
        readonly property bool available: window.desktop ? master.available : matched.length > 0
        readonly property real volume: window.desktop ? master.volume : matched.length ? matched.reduce((sum,n)=>sum+n.audio.volume,0)/matched.length : 0
        readonly property bool muted: window.desktop ? master.muted : matched.length === 0 || matched.every(n=>n.audio.muted)
        readonly property var bands: master.bands
        property real wheelRemainder: 0
        function normalized(value) {return String(value ?? "").toLowerCase().replace(/[^a-z0-9]/g,"").replace(/browser$/,"");}
        function matches(node) {
            if (!node.ready || !node.audio || !window.current) return false;
            const props=node.properties, pid=Number(props["application.process.id"]);
            if (pid>0) return pid===window.current.pid || window.pids.includes(pid);
            const name=normalized(window.current.className);
            return name.length>0 && ["application.id","application.name","application.icon-name","application.process.binary"]
                .some(key=>normalized(props[key])===name);
        }
        function setVolume(value) {
            if (!available || !Number.isFinite(value)) return;
            const bounded=Math.max(0,Math.min(1,value));
            if (window.desktop) master.setVolume(bounded);
            else matched.forEach(node=>{node.audio.volume=bounded;});
        }
        function scroll(delta) {
            if (!available || !Number.isFinite(delta)) return;
            wheelRemainder+=delta;
            const steps=Math.trunc(wheelRemainder/120);
            wheelRemainder-=steps*120;
            if(steps) setVolume(Math.round((volume+steps*0.05)*100)/100);
        }
        onMatchedChanged: wheelRemainder=0
        PwObjectTracker {objects:audio.active ? audio.candidates : []}
    }
  '';

  windowMeterQml = pkgs.writeText "WindowMeter.qml" ''
    import QtQuick

    Item {
        id: meter
        property QtObject glass: null
        property real value: -1
        property string glyph: ""
        property string label: ""
        property bool active: true
        property bool motionEnabled: true
        property real level: value<0 ? 0 : Math.max(0,Math.min(1,value/100))
        property real phase: 0
        implicitWidth: 44
        implicitHeight: 182
        Accessible.role: Accessible.ProgressBar
        Accessible.name: label
        Accessible.description: value<0 ? "Unavailable" : Math.round(value)+"%"
        Behavior on level {NumberAnimation {duration:meter.motionEnabled?280:0;easing.type:Easing.OutCubic}}
        NumberAnimation on phase {
            from:0;to:Math.PI*2;duration:2600;loops:Animation.Infinite
            running:meter.active && meter.motionEnabled && meter.value>=0
        }
        FrostedSurface {
            id: track
            width:parent.width;height:126;radius:14
            glass:meter.glass
            tint:"#bf222222"
            Canvas {
                id: wave
                anchors.fill:parent
                onPaint: {
                    const ctx=getContext("2d");ctx.reset();
                    if(meter.value<0)return;
                    const baseline=height*(1-meter.level);
                    const amplitude=Math.min(6,2+meter.level*4,baseline,height-baseline);
                    ctx.fillStyle="white";ctx.beginPath();ctx.moveTo(0,height);
                    for(let x=0;x<=width;x++) {
                        const y=baseline+Math.sin(x/width*Math.PI*2-meter.phase)*amplitude;
                        ctx.lineTo(x,y);
                    }
                    ctx.lineTo(width,height);ctx.closePath();ctx.fill();
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Component.onCompleted: requestPaint()
                Connections {target:meter;function onPhaseChanged(){wave.requestPaint();}function onLevelChanged(){wave.requestPaint();}function onValueChanged(){wave.requestPaint();}}
            }
        }
        Text {
            y:138;anchors.horizontalCenter:parent.horizontalCenter
            text:meter.glyph;color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:21
        }
        UsageValue {
            y:166;anchors.horizontalCenter:parent.horizontalCenter
            text:meter.value<0?"—":String(Math.round(meter.value));unit:meter.value<0?"":"%";fontSize:11;slots:3
            active:meter.active;motionEnabled:meter.motionEnabled
        }
    }
  '';

  windowInfoQml = pkgs.writeText "WindowInfo.qml" ''
    import QtQuick
    import QtQuick.Controls
    import Quickshell
    import Quickshell.Widgets

    Item {
        id: panel
        required property var window
        required property var usage
        required property var audio
        property QtObject glass: null
        property bool active: true
        property bool motionEnabled: true
        property real now: Date.now()
        readonly property url icon: window.desktop ? "file:///run/current-system/sw/share/icons/hicolor/scalable/apps/nix-snowflake.svg" : window.icons[window.current?.key] || ""
        readonly property string elapsed: {
            const seconds=window.desktop ? 0 : Math.max(0,Math.floor((now-window.born)/1000));
            return [Math.floor(seconds/3600),Math.floor(seconds/60)%60,seconds%60].map(v=>String(v).padStart(2,"0")).join(":");
        }
        readonly property color tint: {
            const colors=palette.colors;
            let chosen=Qt.rgba(21/255,21/255,21/255,1),score=0;
            for(const color of colors) {
                const saturation=Math.max(color.r,color.g,color.b)-Math.min(color.r,color.g,color.b);
                if(color.a>0.5 && saturation>score){score=saturation;chosen=color;}
            }
            const mix=0.18,base=21/255;
            return Qt.rgba(base*(1-mix)+chosen.r*mix,base*(1-mix)+chosen.g*mix,base*(1-mix)+chosen.b*mix,0.75);
        }
        readonly property var readings: window.desktop
            ? [usage.state.cpu,usage.state.ram.percent,usage.state.gpu.percent]
            : window.state.key===window.current?.key ? [window.state.cpu,window.state.ram,window.state.gpu] : [null,null,null]
        implicitWidth:600;implicitHeight:220
        Timer {interval:1000;repeat:true;running:panel.active;triggeredOnStart:true;onTriggered:panel.now=Date.now()}
        ColorQuantizer {id:palette;source:panel.icon;depth:3;rescaleSize:48}
        FrostedSurface {
            anchors.fill:parent;radius:24;glass:panel.glass
            tintGradient:Gradient {
                orientation:Gradient.Horizontal
                GradientStop {position:0;color:panel.tint}
                GradientStop {position:1;color:"#bf151515"}
            }
        }
        // The surface is deliberately read-only; only controls below set a hand cursor.
        ClippingRectangle {
            x:16;y:30;width:160;height:160;radius:28;color:"transparent"
            Image {
                id:appIcon;anchors.fill:parent;anchors.margins:8;source:panel.icon
                fillMode:Image.PreserveAspectFit;asynchronous:true;smooth:true;mipmap:true
                // Rasterize SVGs at the physical display size, including HiDPI screens.
                sourceSize:Qt.size(Math.ceil(width*Screen.devicePixelRatio),Math.ceil(height*Screen.devicePixelRatio))
            }
            Text {
                anchors.centerIn:parent;visible:appIcon.status!==Image.Ready
                text:panel.window.desktop?"":"";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:94
            }
        }
        Text {
            x:192;y:21;width:178;height:44
            text:panel.window.current?.title || "Desktop"
            color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:14
            maximumLineCount:2;wrapMode:Text.Wrap;elide:Text.ElideRight
        }
        MediaButton {
            objectName:"closeActiveWindow"
            x:378;y:17;width:30;height:30;glyph:"";iconSize:18
            glass:panel.glass;motionEnabled:panel.motionEnabled;label:"Close active window"
            enabled:!panel.window.desktop
            onClicked:panel.window.closeWindow()
        }
        Row {
            x:192;y:80;spacing:12
            Repeater {
                model:panel.window.recent
                delegate: MediaButton {
                    id: recentButton
                    required property var modelData
                    objectName:"recent-"+modelData.address
                    width:38;height:38;glass:panel.glass;motionEnabled:panel.motionEnabled
                    label:"Focus "+modelData.title
                    onClicked:panel.window.focusWindow(modelData.address)
                    contentItem: Item {
                        rotation:recentButton.hovered||recentButton.visualFocus?30:0
                        scale:recentButton.hovered||recentButton.visualFocus?1.12:1
                        Behavior on rotation {NumberAnimation {duration:panel.motionEnabled?180:0;easing.type:Easing.OutCubic}}
                        Behavior on scale {NumberAnimation {duration:panel.motionEnabled?180:0;easing.type:Easing.OutCubic}}
                        Image {
                            id:recentIcon;anchors.fill:parent;anchors.margins:8
                            source:panel.window.icons[recentButton.modelData.key] || ""
                            fillMode:Image.PreserveAspectFit;asynchronous:true;smooth:true;mipmap:true
                            sourceSize:Qt.size(Math.ceil(width*1.12*Screen.devicePixelRatio),Math.ceil(height*1.12*Screen.devicePixelRatio))
                        }
                        Text {anchors.centerIn:parent;visible:recentIcon.status!==Image.Ready;text:"";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:22}
                    }
                }
            }
        }
        RollingClock {
            objectName:"windowElapsed"
            x:192;y:139;width:implicitWidth;height:implicitHeight
            clockMode:false;fontSize:17;timeText:panel.window.desktop?"—":panel.elapsed
            active:panel.active;motionEnabled:panel.motionEnabled
        }
        WaveVolume {
            objectName:"windowVolume"
            x:192;y:172;width:216;height:34
            audio:panel.audio;motionEnabled:panel.motionEnabled
            opacity:panel.audio.available?1:0.35
            accessibleLabel:panel.window.desktop?"System volume":"Application volume"
        }
        Repeater {
            model:[{glyph:"",name:"CPU"},{glyph:"",name:"RAM"},{glyph:"󰢮",name:"GPU"}]
            delegate:WindowMeter {
                required property int index
                required property var modelData
                objectName:"window"+modelData.name
                x:428+index*54;y:20;width:42
                glass:panel.glass
                glyph:modelData.glyph;label:modelData.name
                value:panel.readings[index]??-1
                active:panel.active;motionEnabled:panel.motionEnabled
            }
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

        readonly property bool motionEnabled: ${if animationsEnabled then "true" else "false"}

        function beginOpen(module) {
            if (!mainMonitor)
                return;
            expandedState.openWith(module);
        }

        function closeMenu() {
            sessionActions.cancel();
            expandedState.close();
        }

        function toggleMenu() {
            if (expandedState.open)
                closeMenu();
            else
                beginOpen("");
        }

        function openClock() {
            if (expandedState.open)
                expandedState.select("clock");
            else
                beginOpen("clock");
        }

        ExpandedState {
            id: expandedState
            motionEnabled: root.motionEnabled
            onMountedChanged: if (!mounted) visibilityState.menuClosed()
        }

        SessionActions {
            id: sessionActions
            onCommandRequested: command => {
                root.closeMenu();
                Quickshell.execDetached(command);
            }
        }

        AudioService {
            id: audioService
            motionEnabled: root.motionEnabled
        }

        MediaService {
            id: mediaService
            active: expandedState.mounted && expandedState.selected === "media"
        }

        WindowService {
            id: windowService
            active: expandedState.mounted
            onDispatchRequested: command => Hyprland.dispatch(command)
        }

        WindowAudio {
            id: windowAudio
            window: windowService
            master: audioService
            active: expandedState.mounted
        }

        UsageService {
            id: usageService
            active: expandedState.mounted
            expanded: expandedState.open && (expandedState.selected === "usage" || windowService.desktop)
        }

        WeatherService {
            id: weatherService
            active: expandedState.open && expandedState.selected === "clock"
        }

        IpcHandler {
            target: "shell"
            function toggle(): void { root.toggleMenu(); }
        }

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

        Connections {
            target: Hyprland
            function onRawEvent(event) {
                if (event.name === "workspacev2") {
                    const id = Number(event.parse(2)[0]);
                    if (Number.isInteger(id))
                        Qt.callLater(() => visibilityState.workspaceChanged(id));
                }
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

        SkyPositions {
            id: skyPositions
            now: clock.date
            latitude: weatherService.latitude
            longitude: weatherService.longitude
        }

        SystemClock {
            id: clock
            precision: expandedState.selected === "clock" ? SystemClock.Seconds : SystemClock.Minutes
        }

        Variants {
            model: Quickshell.screens.filter(screen => screen.name === "HDMI-A-1")

            PanelWindow {
                id: clockWindow
                required property var modelData
                function contains(item, x, y) {
                    if (!item || !item.visible) return false;
                    const p = item.mapFromItem(clockWindow.contentItem, x, y);
                    return p.x >= 0 && p.y >= 0 && p.x <= item.width && p.y <= item.height;
                }
                function blankClicked(x, y) {
                    if (contains(powerConfirmation, x, y) || contains(windowHeader, x, y)) return;
                    sessionActions.cancel();
                    if (contains(modulePanel, x, y)) {
                        if (moduleDeck.displayed === "media") {
                            const details = dummyTiles.itemAt(0).mediaDetailsItem;
                            const p = details.mapFromItem(clockWindow.contentItem, x, y);
                            details.dismissAt(p.x, p.y);
                        }
                        return;
                    }
                    mediaService.dismissEditor();
                    expandedState.collapse();
                }
                QtObject {
                    id: menuGlass
                    property Item source: expandedState.mounted ? backdrop.blurredScene : null
                    property Item root: clockWindow.contentItem
                    property point origin: Qt.point(0, 0)
                    property real scale: 1
                    property int revision: 0
                    property var layout: [clockWindow.width, clockWindow.height, powerConfirmation.y,
                        powerConfirmation.reveal, expandedState.progress, modules.y, windowHeader.x,
                        modulePanel.x, modulePanel.y, modulePanel.width, modulePanel.height]
                    onLayoutChanged: Qt.callLater(() => { revision++; })
                }
                readonly property real moduleWidth: Math.min(600, width * 0.4 - 32)
                readonly property real detailsScale: moduleWidth / 600
                screen: modelData
                visible: visibilityState.compact || expandedState.mounted

                anchors { top: true; left: true; right: true; bottom: true }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-clock"
                WlrLayershell.keyboardFocus: expandedState.open
                    ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                mask: Region {
                    x: expandedState.mounted ? 0 : modules.x
                    y: expandedState.mounted ? 0 : modules.y
                    width: expandedState.mounted ? clockWindow.width : clockTile.width
                    height: expandedState.mounted ? clockWindow.height : clockTile.height
                    radius: expandedState.mounted ? 0 : clockTile.radius
                }

                Binding {
                    target: visibilityState
                    property: "hoverBounds"
                    value: Qt.rect(modules.x, modules.y, clockTile.width, clockTile.height)
                }

                Binding {
                    target: visibilityState
                    property: "workspaceTransition"
                    value: workspaceBadge.animating || workspaceBadge.progress > 0
                }

                Binding {
                    target: audioService
                    property: "active"
                    value: expandedState.mounted && (expandedState.selected === "media"
                        || windowAudio.available || !!dummyTiles.itemAt(0)?.audioRevealed)
                }

                Region {
                    id: compactBlurRegion
                    item: clockTile
                    radius: clockTile.radius
                }
                BackgroundEffect.blurRegion: expandedState.mounted ? null : compactBlurRegion

                FrostedBackdrop {
                    id: backdrop
                    screen: clockWindow.modelData
                    viewportWidth: clockWindow.width
                    height: clockWindow.height
                    active: expandedState.mounted
                    reveal: expandedState.progress
                    cutouts: [clockTile, dummyTiles.itemAt(0), dummyTiles.itemAt(1)]
                        .filter(tile => tile && tile.visible).map(tile => {
                            // Both capsule parents use window coordinates; read their positions
                            // explicitly so cutouts track every frame of the parent change.
                            return {x: tile.parent.x + tile.x, y: tile.parent.y + tile.y,
                                width: tile.width, height: tile.height, radius: tile.radius};
                        }).concat(Array.from({length: footerButtons.count}, (_, i) => footerButtons.itemAt(i))
                            .filter(button => button && button.visible).map(button => ({
                                x: footer.x + button.x, y: footer.y + button.y,
                                width: button.width, height: button.height, radius: button.radius
                            }))).concat(windowHeader.visible ? [{
                                x: windowHeader.x, y: windowHeader.y, width: windowHeader.width * clockWindow.detailsScale,
                                height: windowHeader.height * clockWindow.detailsScale, radius: 24 * clockWindow.detailsScale
                            }] : []).concat(powerConfirmation.visible ? [{
                                x: powerConfirmation.x, y: powerConfirmation.y,
                                width: powerConfirmation.width, height: powerConfirmation.height,
                                radius: powerConfirmation.radius
                            }] : [])
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: expandedState.open
                    onClicked: event => clockWindow.blankClicked(event.x, event.y)
                }

                MouseArea {
                    // Catch the dismissal click instead of passing it to a window.
                    x: clockWindow.width * 0.4
                    width: clockWindow.width - x
                    height: clockWindow.height
                    enabled: expandedState.open
                    onClicked: root.closeMenu()
                }

                MenuEntrance {
                    id: headerEntrance
                    open: expandedState.open
                    order: 0
                    distance: clockWindow.moduleWidth + 8
                    motionEnabled: root.motionEnabled
                }

                WindowInfo {
                    id: windowHeader
                    objectName: "activeWindowInfo"
                    x: 8 + headerEntrance.offset; y: 8
                    width: 600; height: 220
                    scale: clockWindow.detailsScale
                    transformOrigin: Item.TopLeft
                    visible: expandedState.mounted
                    opacity: expandedState.progress * headerEntrance.progress
                    enabled: expandedState.open
                    window: windowService
                    usage: usageService
                    audio: windowAudio
                    glass: menuGlass
                    active: expandedState.open
                    motionEnabled: root.motionEnabled
                }

                ModuleDeck {
                    id: moduleDeck
                    requested: expandedState.open ? expandedState.selected : ""
                    enterDelay: expandedState.progress < 1 ? 100 : 0
                    motionEnabled: root.motionEnabled
                    onDisplayedChanged: if (displayed !== "media") mediaService.dismissEditor()
                }

                // Reparent the selected capsule into its animated destination; there is one surface.
                Item {
                    id: modulePanel
                    objectName: "modulePanel"
                    readonly property var sourceButton: moduleDeck.displayed === "clock" ? clockTile
                        : dummyTiles.itemAt(moduleDeck.displayed === "media" ? 0 : 1)
                    readonly property real sourceX: moduleDeck.displayed === "clock" ? 0 : sourceButton?.restX ?? 0
                    readonly property real sourceWidth: sourceButton?.compactWidth ?? 58
                    readonly property real targetHeight: (moduleDeck.displayed === "clock" ? 310 : 420) * clockWindow.detailsScale
                    x: modules.x + sourceX * (1 - moduleDeck.progress)
                    y: modules.y + (modules.height + 8) * moduleDeck.progress
                    width: sourceWidth + (clockWindow.moduleWidth - sourceWidth) * moduleDeck.progress
                    height: 31 + (targetHeight - 31) * moduleDeck.progress
                    visible: expandedState.mounted && moduleDeck.displayed !== "" && moduleDeck.progress > 0
                    opacity: expandedState.progress
                    enabled: expandedState.open && moduleDeck.interactive

                }

                Item {
                    id: modules
                    objectName: "moduleButtons"
                    x: 8; y: 8 + (windowHeader.height * clockWindow.detailsScale + 8) * expandedState.progress
                    width: clockWindow.moduleWidth; height: 31
                    z: 1
                    readonly property int extractedIndex: moduleDeck.displayed === "clock" ? 0
                        : moduleDeck.displayed === "media" ? 1 : moduleDeck.displayed === "usage" ? 2 : -1
                    readonly property real vacancy: (modulePanel.sourceWidth + 8) * moduleDeck.progress

                    ModuleTile {
                        id: clockTile
                        objectName: "clockTile"
                        MenuEntrance {
                            id: clockEntrance
                            open: expandedState.open
                            participates: expandedState.clockEntrance
                            motionEnabled: root.motionEnabled
                            order: 1
                            distance: clockTile.compactWidth + modules.x
                        }
                        readonly property real morphProgress: moduleDeck.displayed === "clock" ? moduleDeck.progress : 0
                        parent: morphProgress > 0 ? modulePanel : modules
                        controlledProgress: morphProgress
                        expandedWidth: clockWindow.moduleWidth
                        expandedHeight: 310 * clockWindow.detailsScale
                        x: morphProgress > 0 ? 0 : expandedState.open && expandedState.clockEntrance ? clockEntrance.offset : 0
                        y: 0
                        opacity: morphProgress > 0 ? 1 : expandedState.open && expandedState.clockEntrance ? clockEntrance.progress : 1
                        glassSource: expandedState.mounted ? backdrop.blurredScene : null
                        glassPosition: morphProgress > 0 ? Qt.point(modulePanel.x, modulePanel.y) : Qt.point(modules.x + x, modules.y)
                        glassOpacity: expandedState.progress
                        accessibleLabel: "Open calendar, time and weather"
                        outlineEnabled: !expandedState.mounted
                        clip: !expandedState.mounted || morphProgress > 0
                        visible: visibilityState.compact || expandedState.mounted
                        compactWidth: Math.ceil(clockFace.implicitWidth) + 20 + workspaceBadge.revealWidth
                        motionEnabled: root.motionEnabled
                        onClicked: root.openClock()

                        Item {
                            width: clockTile.compactWidth; height: 31
                            opacity: Math.max(0, 1 - clockTile.morphProgress * 4)
                            visible: opacity > 0
                            RollingClock {
                                id: clockFace
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                timeText: Qt.formatDateTime(clock.date, "HH:mm")
                                active: clockWindow.visible
                                motionEnabled: root.motionEnabled
                            }

                            WorkspaceBadge {
                                id: workspaceBadge
                                anchors.left: clockFace.right
                                height: 31
                                workspaceId: visibilityState.workspaceId
                                expanded: visibilityState.workspaceReveal && !expandedState.mounted
                                active: clockWindow.visible && !visibilityState.fullscreen
                                motionEnabled: root.motionEnabled
                            }
                        }

                        CelestialOutline {
                            id: clockSkyOutline
                            anchors.fill: parent
                            active: expandedState.mounted && clockTile.morphProgress === 0
                            hovered: clockTile.hovered
                            motionEnabled: root.motionEnabled
                            sunPhase: skyPositions.sun.phase
                            moonPhase: skyPositions.moon.phase
                        }
                        ClockDetails {
                            id: clockDetails
                            width: 600; height: 310
                            scale: clockWindow.detailsScale
                            transformOrigin: Item.TopLeft
                            opacity: moduleDeck.contentProgress
                            visible: clockTile.morphProgress > 0 && opacity > 0
                            enabled: visible && moduleDeck.interactive
                            now: clock.date
                            weather: weatherService
                        }

                    }

                    Repeater {
                        id: dummyTiles
                        model: [
                            {key: "media", label: "Media", icon: ""},
                            {key: "usage", label: "Usage", icon: ""}
                        ]
                        delegate: ModuleTile {
                            id: dummy
                            required property var modelData
                            required property int index
                            objectName: modelData.key + "Tile"
                            readonly property real restX: clockTile.compactWidth + 8 + index * 66
                                - (modules.extractedIndex >= 0 && modules.extractedIndex < index + 1 ? modules.vacancy : 0)
                            readonly property real morphProgress: moduleDeck.displayed === modelData.key ? moduleDeck.progress : 0
                            parent: morphProgress > 0 ? modulePanel : modules
                            controlledProgress: morphProgress
                            expandedWidth: clockWindow.moduleWidth
                            expandedHeight: 420 * clockWindow.detailsScale
                            MenuEntrance {
                                id: moduleEntrance
                                open: expandedState.open
                                order: dummy.index + 2
                                distance: dummy.restX + dummy.compactWidth + modules.x
                                motionEnabled: root.motionEnabled
                            }
                            x: morphProgress > 0 ? 0 : restX + moduleEntrance.offset
                            y: 0
                            readonly property alias mediaDetailsItem: mediaDetails
                            readonly property bool audioRevealed: modelData.key === "media"
                                && mediaOutline.visible && (hovered || mediaOutline.progress > 0)
                            glassSource: expandedState.mounted ? backdrop.blurredScene : null
                            glassPosition: morphProgress > 0 ? Qt.point(modulePanel.x, modulePanel.y) : Qt.point(modules.x + x, modules.y)
                            glassOpacity: expandedState.progress
                            accessibleLabel: modelData.key === "media" ? audioService.description : "Open " + modelData.label
                            outlineEnabled: false
                            clip: modelData.key !== "media" || morphProgress > 0
                            compactWidth: modelData.key === "media" ? 58 : Math.ceil(label.implicitWidth) + 20
                            motionEnabled: root.motionEnabled
                            visible: expandedState.mounted
                            enabled: expandedState.open
                            opacity: morphProgress > 0 ? 1 : expandedState.progress * moduleEntrance.progress
                            wheelEnabled: modelData.key === "media"
                            onScrolled: delta => audioService.scroll(delta)
                            onClicked: expandedState.select(modelData.key)

                            Text {
                                id: label
                                x: dummy.modelData.key === "media" ? (dummy.compactWidth - width) / 2 : 10
                                y: (31 - height) / 2
                                text: dummy.modelData.key === "media" ? audioService.icon : dummy.modelData.label
                                color: "#ffffff"
                                font.family: "0xProto Nerd Font Mono"
                                font.pixelSize: dummy.modelData.key === "media" ? 18 : 12
                                opacity: Math.max(0, 1 - dummy.morphProgress * 4)
                            }

                            AudioOutline {
                                id: mediaOutline
                                width: dummy.width; height: dummy.height
                                visible: dummy.modelData.key === "media" && dummy.morphProgress === 0
                                muted: audioService.muted
                                bands: audioService.bands
                                hovered: dummy.hovered
                                motionEnabled: root.motionEnabled
                            }

                            UsageOutline {
                                objectName: "usageOutline"
                                anchors.fill: parent
                                visible: dummy.modelData.key === "usage" && dummy.morphProgress === 0
                                active: visible
                                hovered: dummy.hovered
                                cpu: usageService.state.cpu ?? 0
                                ram: usageService.state.ram.percent ?? 0
                                motionEnabled: root.motionEnabled
                            }
                            MediaDetails {
                                id: mediaDetails
                                glassSource: dummy.glassSource
                                glassPosition: dummy.glassPosition
                                width: 600; height: 420
                                scale: clockWindow.detailsScale
                                transformOrigin: Item.TopLeft
                                opacity: moduleDeck.contentProgress
                                visible: dummy.modelData.key === "media" && dummy.morphProgress > 0 && opacity > 0
                                enabled: visible && moduleDeck.interactive
                                media: mediaService
                                audio: audioService
                                motionEnabled: root.motionEnabled
                            }

                            UsageDetails {
                                objectName: "usageDetails"
                                width: 600; height: 420
                                scale: clockWindow.detailsScale
                                transformOrigin: Item.TopLeft
                                glassSource: dummy.glassSource
                                glassPosition: dummy.glassPosition
                                opacity: moduleDeck.contentProgress
                                visible: dummy.modelData.key === "usage" && dummy.morphProgress > 0 && opacity > 0
                                enabled: visible && moduleDeck.interactive
                                active: expandedState.open && visible
                                usage: usageService
                                motionEnabled: root.motionEnabled
                            }

                        }
                    }
                }

                Item {
                    id: footer
                    x: 8; y: clockWindow.height - height - 8
                    width: 158; height: 46
                    visible: expandedState.mounted
                    Repeater {
                        id: footerButtons
                        model: [
                            {action:"poweroff", glyph:"", label:"Shut down"},
                            {action:"reboot", glyph:"", label:"Restart"},
                            {action:"rebuild", glyph:"", label:"Rebuild configuration"}
                        ]
                        delegate: ModuleTile {
                            id: actionButton
                            required property var modelData
                            required property int index
                            objectName: "session-" + modelData.action
                            MenuEntrance {
                                id: actionEntrance
                                open: expandedState.open
                                order: actionButton.index + 4
                                distance: actionButton.index * 56 + 54
                                motionEnabled: root.motionEnabled
                            }
                            x: index * 56 + actionEntrance.offset
                            height: 46; radius: 23; compactWidth: 46
                            visible: expandedState.mounted && opacity > 0
                            opacity: expandedState.progress * actionEntrance.progress
                            glassSource: expandedState.mounted ? backdrop.blurredScene : null
                            glassPosition: Qt.point(footer.x + x, footer.y + y)
                            glassOpacity: expandedState.progress
                            accessibleLabel: modelData.label
                            motionEnabled: root.motionEnabled
                            onClicked: sessionActions.request(modelData.action)
                            Text {
                                anchors.centerIn: parent
                                text: actionButton.modelData.glyph
                                color: "white"; font.family: "0xProto Nerd Font Mono"; font.pixelSize: 24
                            }
                        }
                    }
                }

                FrostedSurface {
                    id: powerConfirmation
                    objectName: "sessionConfirmation"
                    property real reveal: sessionActions.confirming && expandedState.open ? 1 : 0
                    Behavior on reveal { NumberAnimation {duration: root.motionEnabled ? 180 : 0;easing.type:Easing.OutCubic} }
                    x: 8; y: footer.y - height - 12 + 8 * (1-reveal)
                    width: 228; height: 112; radius: 24
                    glass: menuGlass
                    visible: reveal > 0
                    enabled: sessionActions.confirming && expandedState.open
                    opacity: reveal * expandedState.progress
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 18
                        text: "Are you sure?"
                        color: "white"; font.family: "0xProto Nerd Font Mono"; font.pixelSize: 14
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 54; spacing: 12
                        MediaButton {
                            objectName: "cancelSessionAction"
                            width: 40; height: 40; glyph: ""; iconSize: 23
                            label: "Cancel"; glass: menuGlass; motionEnabled: root.motionEnabled
                            onClicked: sessionActions.cancel()
                        }
                        MediaButton {
                            objectName: "confirmSessionAction"
                            width: 40; height: 40; glyph: ""; iconSize: 23
                            label: sessionActions.pending === "poweroff" ? "Confirm shutdown" : "Confirm restart"
                            glass: menuGlass; motionEnabled: root.motionEnabled
                            enabled: sessionActions.confirming
                            onClicked: sessionActions.confirm()
                        }
                    }
                }
            }
        }
    }
  '';
in {
  home.packages = [ pkgs.quickshell ];

  xdg.configFile."quickshell/PlaylistBackend.py".source = playlistBackendPython;
  xdg.configFile."quickshell/MediaService.qml".source = mediaServiceQml;
  xdg.configFile."quickshell/FrostedSurface.qml".source = frostedSurfaceQml;
  xdg.configFile."quickshell/PlaylistScrollBar.qml".source = playlistScrollBarQml;
  xdg.configFile."quickshell/MediaButton.qml".source = mediaButtonQml;
  xdg.configFile."quickshell/WaveVolume.qml".source = waveVolumeQml;
  xdg.configFile."quickshell/MediaTrackRow.qml".source = mediaTrackRowQml;
  xdg.configFile."quickshell/MediaMorphPanel.qml".source = mediaMorphPanelQml;
  xdg.configFile."quickshell/MediaDetails.qml".source = mediaDetailsQml;
  xdg.configFile."quickshell/SkyPositions.qml".source = skyPositionsQml;
  xdg.configFile."quickshell/CelestialOutline.qml".source = celestialOutlineQml;
  xdg.configFile."quickshell/AudioService.qml".source = audioServiceQml;
  xdg.configFile."quickshell/AudioOutline.qml".source = audioOutlineQml;
  xdg.configFile."quickshell/MenuEntrance.qml".source = menuEntranceQml;
  xdg.configFile."quickshell/SessionActions.qml".source = sessionActionsQml;
  xdg.configFile."quickshell/ExpandedState.qml".source = expandedStateQml;
  xdg.configFile."quickshell/ModuleDeck.qml".source = moduleDeckQml;
  xdg.configFile."quickshell/ModuleTile.qml".source = moduleTileQml;
  xdg.configFile."quickshell/CalendarView.qml".source = calendarViewQml;
  xdg.configFile."quickshell/WeatherService.qml".source = weatherServiceQml;
  xdg.configFile."quickshell/BackdropGeometry.qml".source = backdropGeometryQml;
  xdg.configFile."quickshell/FrostedBackdrop.qml".source = frostedBackdropQml;
  xdg.configFile."quickshell/ClockDetails.qml".source = clockDetailsQml;
  xdg.configFile."quickshell/UsageBackend.py".source = usageBackendPython;
  xdg.configFile."quickshell/UsageService.qml".source = usageServiceQml;
  xdg.configFile."quickshell/UsageOutline.qml".source = usageOutlineQml;
  xdg.configFile."quickshell/UsageValue.qml".source = usageValueQml;
  xdg.configFile."quickshell/UsageDetails.qml".source = usageDetailsQml;
  xdg.configFile."quickshell/WindowBackend.py".source = windowBackendPython;
  xdg.configFile."quickshell/WindowService.qml".source = windowServiceQml;
  xdg.configFile."quickshell/WindowAudio.qml".source = windowAudioQml;
  xdg.configFile."quickshell/WindowMeter.qml".source = windowMeterQml;
  xdg.configFile."quickshell/WindowInfo.qml".source = windowInfoQml;
  xdg.configFile."quickshell/shell.qml".source = shellQml;
  xdg.configFile."quickshell/ClockVisibility.qml".source = visibilityQml;
  xdg.configFile."quickshell/RollingClock.qml".source = rollingClockQml;
  xdg.configFile."quickshell/HoverOutline.qml".source = hoverOutlineQml;
  xdg.configFile."quickshell/WorkspaceBadge.qml".source = workspaceBadgeQml;

  # Compositor fades include the glass blur. Unmapping leaves no hidden surface
  # or residual frosted patch; disabling compositor animations is respected.
  wayland.windowManager.hyprland.settings.bind = [
    ", Super_L, exec, ${pkgs.quickshell}/bin/qs ipc call shell toggle"
    ", Super_R, exec, ${pkgs.quickshell}/bin/qs ipc call shell toggle"
  ];

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
