{ config ? {}, lib ? pkgs.lib, pkgs, ... }:
let
  animationsEnabled = config.wayland.windowManager.hyprland.settings.config.animations.enabled or true;
  chromium = config.programs.chromium.finalPackage or pkgs.chromium;

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
            if (!["clock", "media", "usage", "network", "apps", "ai"].includes(module))
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
        property QtObject glass: null
        property bool motionEnabled: true
        property date today: new Date()
        property int monthOffset: 0
        property date selectedDate: today
        readonly property date month: new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)
        readonly property string title: Qt.formatDateTime(month, "MMMM yyyy")
        readonly property int firstDay: (month.getDay() + 6) % 7
        readonly property int daysInMonth: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
        readonly property string selectedLabel: Qt.formatDateTime(selectedDate, "dddd, d MMMM")
        readonly property bool away: monthOffset !== 0 || !sameDay(selectedDate, today)

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
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: navigation.verticalCenter
            width: parent.width - navigation.width - 12
            text: calendar.title
            color: "white"
            font.family: "0xProto Nerd Font Mono"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Row {
            id: navigation
            anchors.right: parent.right
            spacing: 6
            MediaButton {
                objectName: "previousMonth"
                width: 30; height: 30; iconSize: 11
                glyph: ""; label: "Previous month"
                glass: calendar.glass; motionEnabled: calendar.motionEnabled
                onClicked: calendar.monthOffset -= 1
            }
            MediaButton {
                objectName: "nextMonth"
                width: 30; height: 30; iconSize: 11
                glyph: ""; label: "Next month"
                glass: calendar.glass; motionEnabled: calendar.motionEnabled
                onClicked: calendar.monthOffset += 1
            }
        }

        Grid {
            id: weekdays
            y: 44
            columns: 7
            width: parent.width
            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]
                Text {
                    required property string modelData
                    required property int index
                    width: weekdays.width / 7
                    height: 20
                    text: modelData
                    color: index >= 5 ? "#666666" : "#888888"
                    font.family: "0xProto Nerd Font Mono"
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Grid {
            id: days
            y: 64
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
                    height: 26
                    hoverEnabled: true
                    Accessible.name: Qt.formatDateTime(value, "dddd, d MMMM yyyy")
                    onClicked: calendar.selectedDate = value
                    background: Rectangle {
                        anchors.centerIn: parent
                        width: 25; height: 25; radius: 12.5
                        color: day.isToday ? "#ffffff"
                            : day.chosen ? "#38ffffff"
                            : day.hovered || day.visualFocus ? "#1cffffff" : "transparent"
                        Behavior on color { ColorAnimation { duration: calendar.motionEnabled ? 140 : 0 } }
                    }
                    contentItem: Text {
                        text: day.value.getDate()
                        color: day.isToday ? "#151515" : day.inMonth ? "#ffffff" : "#555555"
                        font.family: "0xProto Nerd Font Mono"
                        font.pixelSize: 11
                        font.weight: day.isToday ? Font.DemiBold : Font.Normal
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
            height: 22
            hoverEnabled: true
            Accessible.name: "Return to today"
            onClicked: calendar.reset()
            background: Item {}
            contentItem: Item {
                Text {
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - todayHint.width - 12
                    text: calendar.selectedLabel
                    color: todayButton.hovered || todayButton.visualFocus ? "#ffffff" : "#aaaaaa"
                    font.family: "0xProto Nerd Font Mono"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                Text {
                    id: todayHint
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Today "
                    visible: calendar.away
                    color: todayButton.hovered || todayButton.visualFocus ? "#ffffff" : "#777777"
                    font.family: "0xProto Nerd Font Mono"
                    font.pixelSize: 9
                }
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
        property Item glassSource: null
        property point glassPosition: Qt.point(0, 0)
        property bool active: true
        property bool motionEnabled: true
        readonly property alias calendar: calendar
        // Same 18-22% accent wash as the active-window card, keyed to the sky.
        readonly property color weatherTint: {
            const code = weather.code ?? 0, day = weather.daylight ?? true;
            const accent = !weather.available ? [21, 21, 21]
                : code <= 1 ? (day ? [232, 176, 79] : [111, 120, 216])
                : code <= 3 ? [139, 155, 176]
                : code <= 48 ? [154, 163, 171]
                : code <= 67 || (code >= 80 && code <= 82) ? [79, 143, 224]
                : code <= 86 ? [188, 216, 239] : [146, 102, 224];
            const mix = 0.22, base = 21 / 255;
            return Qt.rgba(base * (1 - mix) + accent[0] / 255 * mix,
                base * (1 - mix) + accent[1] / 255 * mix,
                base * (1 - mix) + accent[2] / 255 * mix, 0.75);
        }
        width: 600; height: 310

        function isoWeek(date) {
            const thursday = new Date(date.getFullYear(), date.getMonth(), date.getDate() - (date.getDay() + 6) % 7 + 3);
            const firstThursday = new Date(thursday.getFullYear(), 0, 4);
            return 1 + Math.round(((thursday - firstThursday) / 86400000 - 3 + (firstThursday.getDay() + 6) % 7) / 7);
        }
        function dayOfYear(date) {
            return Math.round((new Date(date.getFullYear(), date.getMonth(), date.getDate())
                - new Date(date.getFullYear(), 0, 1)) / 86400000) + 1;
        }

        QtObject {
            id: glassContext
            property Item source: details.glassSource
            property Item root: details
            property point origin: details.glassPosition
            property real scale: details.scale
            property int revision: 0
            property var layout: [origin.x, origin.y, scale, details.width, details.height]
            onLayoutChanged: Qt.callLater(() => { revision++; })
        }

        FrostedSurface {
            x: 20; y: 20
            width: 300; height: 270; radius: 22
            glass: glassContext; tint: "#bf222222"
            CalendarView {
                id: calendar
                x: 14; y: 14
                width: parent.width - 28; height: parent.height - 24
                today: details.now
                glass: glassContext
                motionEnabled: details.motionEnabled
            }
        }

        FrostedSurface {
            id: timeCard
            x: 332; y: 20
            width: 248; height: 104; radius: 22
            glass: glassContext; tint: "#bf222222"
            RollingClock {
                objectName: "clockDetailsTime"
                x: 18; y: 14
                width: implicitWidth; height: implicitHeight
                clockMode: false; fontSize: 36
                timeText: Qt.formatDateTime(details.now, "HH:mm:ss")
                active: details.active && details.visible
                motionEnabled: details.motionEnabled
            }
            Text {
                x: 18; y: parent.height - height - 16
                width: parent.width - zone.width - 44
                text: "Week " + details.isoWeek(details.now) + "  ·  Day " + details.dayOfYear(details.now)
                color: "#aaaaaa"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
            Text {
                id: zone
                anchors.right: parent.right; anchors.rightMargin: 18
                y: parent.height - height - 16
                text: Qt.formatDateTime(details.now, "t")
                color: "#777777"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 10
            }
        }

        FrostedSurface {
            id: weatherCard
            objectName: "weatherCard"
            x: 332; y: 136
            width: 248; height: 154; radius: 22
            glass: glassContext
            tintGradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: details.weatherTint }
                GradientStop { position: 1; color: "#bf151515" }
            }
            Text {
                x: 18; y: 17
                width: parent.width - credit.width - 40
                text: "  " + details.weather.city
                color: "#aaaaaa"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
            AbstractButton {
                id: credit
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                anchors.right: parent.right; anchors.rightMargin: 12
                y: 10
                width: creditLabel.implicitWidth + 12; height: 24
                hoverEnabled: true
                Accessible.name: details.weather.available ? "Weather by Open-Meteo" : "Retry weather"
                onClicked: {
                    if (details.weather.available)
                        Qt.openUrlExternally("https://open-meteo.com/");
                    else
                        details.weather.refresh();
                }
                background: Item {}
                contentItem: Text {
                    id: creditLabel
                    text: details.weather.available ? "Open-Meteo ↗" : details.weather.loading ? "Open-Meteo" : "Retry ↻"
                    color: credit.hovered || credit.visualFocus ? "#ffffff" : "#777777"
                    font.family: "0xProto Nerd Font Mono"
                    font.pixelSize: 9
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                x: 16; y: 34
                text: details.weather.temperatureText
                color: "white"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 42
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 22
                y: 42
                text: details.weather.available ? details.weather.icon : ""
                color: details.weather.available ? "#ffffff" : "#555555"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 36
            }
            Text {
                x: 18; y: 92
                width: parent.width - 36
                text: details.weather.status
                color: "#dddddd"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            Row {
                x: 14; y: 116
                spacing: 6
                visible: details.weather.available
                Repeater {
                    model: [
                        {glyph: "", text: "Feels " + Math.round(details.weather.feelsLike) + "°"},
                        {glyph: "󰖝", text: Math.round(details.weather.wind) + " km/h"}
                    ]
                    delegate: FrostedSurface {
                        id: chipSurface
                        required property var modelData
                        width: chip.implicitWidth + 20; height: 24; radius: 12
                        glass: glassContext; tint: "#bf2a2a2a"
                        Text {
                            id: chip
                            anchors.centerIn: parent
                            text: chipSurface.modelData.glyph + " " + chipSurface.modelData.text
                            color: "#cccccc"
                            font.family: "0xProto Nerd Font Mono"
                            font.pixelSize: 9
                        }
                    }
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
    import Quickshell.Widgets

    Item {
        id:details
        required property var usage
        property Item glassSource:null
        property point glassPosition:Qt.point(0,0)
        property bool active:false
        property bool motionEnabled:true
        property real phase:0
        readonly property var down:rate(usage.state.network.download)
        readonly property var up:rate(usage.state.network.upload)
        width:600;height:420
        function fixed(value,decimals) {return typeof value==="number"&&Number.isFinite(value)?value.toFixed(decimals):"—";}
        function gib(value) {return typeof value==="number"?fixed(value/1073741824,1):"—";}
        function percent(value) {return typeof value==="number"&&Number.isFinite(value)?value:-1;}
        function rate(value) {
            if(typeof value!=="number"||!Number.isFinite(value))return {text:"—",unit:"KiB/s"};
            const units=["B/s","KiB/s","MiB/s","GiB/s"];
            let index=0;
            while(value>=1024&&index<3){value/=1024;index++;}
            return {text:value.toFixed(index===0?0:1),unit:units[index]};
        }
        NumberAnimation on phase {
            from:0;to:Math.PI*2;duration:2600;loops:Animation.Infinite
            running:details.active&&details.motionEnabled
        }
        QtObject {
            id:glassContext
            property Item source:details.glassSource
            property Item root:details
            property point origin:details.glassPosition
            property real scale:details.scale
            property int revision:0
            property var layout:[origin.x,origin.y,scale,details.width,details.height]
            onLayoutChanged:Qt.callLater(()=>{revision++;})
        }

        // A frosted card whose reading rises from the bottom as a slow liquid
        // wave, echoing the active-window meters.
        component LiquidCard: FrostedSurface {
            id:card
            property string glyph:""
            property string label:""
            property string caption:""
            property real value:-1
            property color accent:"white"
            readonly property real level:value<0?0:Math.max(0,Math.min(1,value/100))
            property real shownLevel:level
            Behavior on shownLevel {NumberAnimation{duration:details.motionEnabled?280:0;easing.type:Easing.OutCubic}}
            width:176;height:196;radius:22
            glass:glassContext;tint:"#bf222222"
            Accessible.role:Accessible.ProgressBar
            Accessible.name:label
            Accessible.description:value<0?"Unavailable":Math.round(value)+"%"
            Canvas {
                id:liquid
                anchors.fill:parent
                function rgba(alpha) {
                    return "rgba("+Math.round(card.accent.r*255)+","+Math.round(card.accent.g*255)+","+Math.round(card.accent.b*255)+","+alpha+")";
                }
                onPaint: {
                    const ctx=getContext("2d");ctx.reset();
                    if(card.value<0||card.shownLevel<=0)return;
                    const baseline=height*(1-card.shownLevel);
                    const amplitude=Math.min(4,1.5+card.shownLevel*3,baseline,height-baseline);
                    const crest=x=>baseline+Math.sin(x/width*Math.PI*2-details.phase)*amplitude;
                    const fill=ctx.createLinearGradient(0,baseline-amplitude,0,height);
                    fill.addColorStop(0,rgba(0.26));fill.addColorStop(1,rgba(0.06));
                    ctx.fillStyle=fill;ctx.beginPath();ctx.moveTo(0,height);
                    for(let x=0;x<=width;x+=2)ctx.lineTo(x,crest(x));
                    ctx.lineTo(width,height);ctx.closePath();ctx.fill();
                    ctx.strokeStyle=rgba(0.75);ctx.lineWidth=1.5;ctx.beginPath();
                    for(let x=0;x<=width;x+=2)x===0?ctx.moveTo(x,crest(x)):ctx.lineTo(x,crest(x));
                    ctx.stroke();
                }
                onWidthChanged:requestPaint()
                onHeightChanged:requestPaint()
                Component.onCompleted:requestPaint()
                Connections {target:details;function onPhaseChanged(){liquid.requestPaint();}}
                Connections {target:card;function onShownLevelChanged(){liquid.requestPaint();}function onValueChanged(){liquid.requestPaint();}}
            }
            Text {x:16;y:15;text:card.glyph;color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:18}
            Text {x:42;y:18;text:card.label;color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:12}
            Text {
                x:16;y:card.height-height-16;width:card.width-32
                text:card.caption;color:"#aaaaaa"
                font.family:"0xProto Nerd Font Mono";font.pixelSize:9;elide:Text.ElideRight
            }
        }

        component Detail: Row {
            property alias value:reading.text
            property alias unit:reading.unit
            property alias slots:reading.slots
            property alias valueName:reading.objectName
            property string suffix:""
            spacing:5
            UsageValue {
                id:reading
                fontSize:16;slots:3
                active:details.active;motionEnabled:details.motionEnabled
            }
            Text {
                height:reading.height;verticalAlignment:Text.AlignBottom;bottomPadding:2
                visible:text!=="";text:parent.suffix;color:"#888888"
                font.family:"0xProto Nerd Font Mono";font.pixelSize:10
            }
        }

        Row {
            x:20;y:20;spacing:16
            LiquidCard {
                objectName:"usageCpuCard"
                glyph:"";label:"CPU";accent:"#ead178"
                value:details.percent(details.usage.state.cpu)
                caption:details.usage.state.cpuName||"Processor"
                UsageValue {
                    objectName:"usageCpu"
                    x:16;y:54;text:details.fixed(details.usage.state.cpu,0);unit:"%";fontSize:38;slots:0
                    active:details.active;motionEnabled:details.motionEnabled
                }
                Detail {
                    x:16;y:112;valueName:"usageTemperature"
                    value:details.fixed(details.usage.state.temperature,0);unit:"°C"
                }
            }
            LiquidCard {
                objectName:"usageRamCard"
                glyph:"󰍛";label:"RAM";accent:"#9acb92"
                value:details.percent(details.usage.state.ram.percent)
                caption:"Memory in use"
                UsageValue {
                    objectName:"usageRamPercent"
                    x:16;y:54;text:details.fixed(details.usage.state.ram.percent,0);unit:"%";fontSize:38;slots:0
                    active:details.active;motionEnabled:details.motionEnabled
                }
                Detail {
                    x:16;y:112;valueName:"usageRam"
                    value:details.gib(details.usage.state.ram.used);unit:"GiB";slots:4
                    suffix:"/ "+details.gib(details.usage.state.ram.total)
                }
            }
            LiquidCard {
                objectName:"usageGpuCard"
                glyph:"󰢮";label:"GPU";accent:"#8fb5e8"
                value:details.percent(details.usage.state.gpu.percent)
                caption:(details.usage.state.gpu.name??"").replace("NVIDIA GeForce ","")||"Graphics"
                UsageValue {
                    objectName:"usageGpu"
                    x:16;y:54;text:details.fixed(details.usage.state.gpu.percent,0);unit:"%";fontSize:38;slots:0
                    active:details.active;motionEnabled:details.motionEnabled
                }
                Detail {
                    x:16;y:112;valueName:"usageVram"
                    value:details.gib(details.usage.state.gpu.used);unit:"GiB";slots:4
                    suffix:"/ "+details.gib(details.usage.state.gpu.total)
                }
            }
        }

        FrostedSurface {
            id:coresCard
            x:20;y:232;width:352;height:168;radius:22
            glass:glassContext;tint:"#bf222222"
            Text {x:16;y:15;text:"Cores";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:12}
            Text {
                anchors.right:parent.right;anchors.rightMargin:16;y:16
                text:cores.count?cores.count+" threads":"";color:"#888888"
                font.family:"0xProto Nerd Font Mono";font.pixelSize:10
            }
            Row {
                id:coreBars
                objectName:"usageCores"
                readonly property real gap:cores.count>16?3:6
                readonly property bool labelled:cores.count<=16
                x:16;y:44;width:parent.width-32;height:parent.height-y-14
                spacing:gap
                Repeater {
                    id:cores
                    model:details.usage.coresModel
                    delegate:Item {
                        id:coreCell
                        required property int index
                        readonly property var core:details.usage.state.cores[index]??({})
                        readonly property real level:typeof core.percent==="number"?Math.max(0,Math.min(1,core.percent/100)):0
                        width:cores.count?(coreBars.width-coreBars.gap*(cores.count-1))/cores.count:0
                        height:coreBars.height
                        Accessible.role:Accessible.ProgressBar
                        Accessible.name:"Core "+((core.id??index)+1)
                        Accessible.description:typeof core.percent==="number"?Math.round(core.percent)+"%":"Unavailable"
                        // Clip a flat fill to the rounded track so 5% and 12% stay distinct.
                        ClippingRectangle {
                            id:track
                            width:parent.width;height:parent.height-(coreBars.labelled?18:0)
                            radius:Math.min(width/2,8);color:"#1affffff"
                            Rectangle {
                                anchors.bottom:parent.bottom
                                width:parent.width;height:parent.height*coreCell.level
                                color:"#ead178";opacity:0.85
                                Behavior on height {NumberAnimation{duration:details.motionEnabled?280:0;easing.type:Easing.OutCubic}}
                            }
                        }
                        Text {
                            anchors.horizontalCenter:parent.horizontalCenter;anchors.bottom:parent.bottom
                            visible:coreBars.labelled
                            text:typeof coreCell.core.percent==="number"?Math.round(coreCell.core.percent):"—"
                            color:"#aaaaaa";font.family:"0xProto Nerd Font Mono";font.pixelSize:9
                        }
                    }
                }
            }
            Text {
                anchors.centerIn:parent;visible:cores.count===0
                text:"Waiting for samples…";color:"#888888"
                font.family:"0xProto Nerd Font Mono";font.pixelSize:10
            }
        }

        FrostedSurface {
            x:384;y:232;width:196;height:168;radius:22
            glass:glassContext;tint:"#bf222222"
            Text {x:16;y:15;text:"󰛳";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:18}
            Text {x:42;y:18;text:"Network";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:12}
            Repeater {
                model:[{glyph:"",name:"usageDownload",label:"Download"},{glyph:"",name:"usageUpload",label:"Upload"}]
                delegate:Item {
                    required property int index
                    required property var modelData
                    readonly property var reading:index===0?details.down:details.up
                    x:16;y:52+index*40;width:164;height:32
                    Accessible.name:modelData.label
                    Accessible.description:reading.text+" "+reading.unit
                    Text {
                        anchors.verticalCenter:parent.verticalCenter
                        text:parent.modelData.glyph;color:"#aaaaaa"
                        font.family:"0xProto Nerd Font Mono";font.pixelSize:13
                    }
                    UsageValue {
                        objectName:parent.modelData.name
                        x:24;anchors.verticalCenter:parent.verticalCenter
                        text:parent.reading.text;unit:parent.reading.unit;fontSize:20;slots:5
                        active:details.active;motionEnabled:details.motionEnabled
                    }
                }
            }
            Text {
                x:16;y:parent.height-height-16;width:parent.width-32
                text:(details.usage.state.network.interfaces??[]).join(", ")||"No interface"
                color:"#aaaaaa";font.family:"0xProto Nerd Font Mono";font.pixelSize:9;elide:Text.ElideRight
            }
        }
    }
  '';

  networkBackendPython = pkgs.writeText "NetworkBackend.py" ''
    """Read-only connection snapshots; explicit user actions never reset Tailscale prefs."""
    import argparse
    import getpass
    import ipaddress
    import json
    import os
    from pathlib import Path
    import re
    import signal
    import subprocess
    import sys
    import threading


    def split_fields(text):
        fields, value, escaped = [], ''', False
        for char in text:
            if escaped:
                value += char
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == ':':
                fields.append(value)
                value = '''
            else:
                value += char
        fields.append(value + ('\\' if escaped else '''))
        return fields


    def device_info(text):
        result = {}
        for line in text.splitlines():
            key, separator, value = line.partition(':')
            if separator:
                result.setdefault(re.sub(r'\[\d+\]$', ''', key), []).append(':'.join(split_fields(value)))
        return result


    def read(path):
        try:
            return path.read_text().strip()
        except (OSError, UnicodeError):
            return '''


    def ipv4(values):
        for value in values or []:
            try:
                ip = ipaddress.ip_address(value)
                if ip.version == 4:
                    return str(ip)
            except ValueError:
                pass
        return '''


    def tail_state(raw):
        if not isinstance(raw, dict):
            return {'available':False, 'status':'Unavailable', 'running':False, 'name':''', 'ip':''', 'peers':[], 'exitNode':''', 'operator':False}
        state = raw.get('BackendState') or 'Unavailable'
        own = raw.get('Self') or {}
        peers = []
        for key, peer in (raw.get('Peer') or {}).items():
            if not isinstance(peer, dict):
                continue
            peers.append({'key':str(peer.get('ID') or key), 'name':str(peer.get('HostName') or peer.get('DNSName',''').rstrip('.') or 'Device'),
                          'ip':ipv4(peer.get('TailscaleIPs')), 'online':peer.get('Online') is True,
                          'os':str(peer.get('OS') or '''), 'exitNode':peer.get('ExitNodeOption') is True,
                          'selected':peer.get('ExitNode') is True})
        peers.sort(key=lambda p: (not p['online'], p['name'].casefold(), p['key']))
        return {'available':True, 'status':state, 'running':state=='Running',
                'name':str(own.get('HostName') or '''), 'ip':ipv4(raw.get('TailscaleIPs') or own.get('TailscaleIPs')),
                'peers':peers, 'exitNode':next((p['ip'] for p in peers if p['selected']), '''), 'operator':False}


    class Backend:
        def __init__(self, nmcli='nmcli', tailscale='tailscale', proc=Path('/proc'), sysfs=Path('/sys'), runner=subprocess.run):
            self.nmcli, self.tailscale, self.proc, self.sysfs, self.runner = nmcli, tailscale, proc, sysfs, runner

        def run(self, command, timeout=2):
            try:
                return self.runner(command, capture_output=True, text=True, timeout=timeout,
                                   env={**os.environ, 'LC_ALL':'C', 'NO_COLOR':'1'}, check=False)
            except (OSError, subprocess.TimeoutExpired):
                return subprocess.CompletedProcess(command, 1, ''', ''')

        def json(self, command):
            result = self.run(command)
            try:
                return json.loads(result.stdout) if result.returncode == 0 else None
            except ValueError:
                return None

        def network(self):
            result = self.run([self.nmcli, '-t', '-f', 'DEVICE,TYPE,STATE,CONNECTION', 'device', 'status'])
            devices = [row for row in (split_fields(line) for line in result.stdout.splitlines())
                       if len(row) == 4 and row[1] in ('ethernet','wifi')]
            defaults = []
            for line in read(self.proc/'net/route').splitlines()[1:]:
                row = line.split()
                try:
                    if row[1]=='00000000' and int(row[3],16)&2:
                        defaults.append((int(row[6]), row[0]))
                except (ValueError, IndexError):
                    pass
            preferred = min(defaults)[1] if defaults else '''
            devices.sort(key=lambda d: (not d[2].startswith('connected'), d[0]!=preferred, d[1]!='ethernet', d[0]))
            if not devices:
                return {'available':result.returncode==0, 'connected':False, 'state':'Disconnected' if result.returncode==0 else 'Unavailable',
                        'interface':''', 'name':'No connection', 'type':''', 'address':''', 'gateway':''', 'dns':[], 'speed':None, 'received':None, 'sent':None}
            interface, kind, status, name = devices[0]
            fields = self.run([self.nmcli, '-t', '-m', 'multiline', '-f',
                              'GENERAL.STATE,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS', 'device', 'show', interface])
            info = device_info(fields.stdout)
            def first(key):
                return next((v for v in info.get(key,[]) if v and v!='--'), ''')
            connected = status.startswith('connected') and fields.returncode==0
            root = self.sysfs/'class/net'/interface
            def counter(path):
                value = read(root/path)
                return int(value) if value.isdigit() else None
            connectivity = self.run([self.nmcli, '-g', 'CONNECTIVITY', 'general', 'status']).stdout.strip()
            state = ('Captive portal' if connectivity=='portal' else 'Limited' if connectivity=='limited' else 'Connected') if connected else 'Connecting' if status.startswith('connecting') else 'Disconnected'
            return {'available':result.returncode==0, 'connected':connected, 'state':state,
                    'interface':interface, 'name':name if name and name!='--' else interface, 'type':kind,
                    'address':first('IP4.ADDRESS').split('/')[0] if connected else ''', 'gateway':first('IP4.GATEWAY') if connected else ''',
                    'dns':[v for v in info.get('IP4.DNS',[]) if v and v!='--'] if connected else [], 'speed':counter(Path('speed')) if connected else None,
                    'received':counter(Path('statistics/rx_bytes')) if connected else None, 'sent':counter(Path('statistics/tx_bytes')) if connected else None}

        def tails(self):
            state = tail_state(self.json([self.tailscale, 'status', '--json']))
            prefs = self.json([self.tailscale, 'debug', 'prefs']) if state['available'] else None
            state['operator'] = os.geteuid()==0 or isinstance(prefs,dict) and prefs.get('OperatorUser')==getpass.getuser()
            return state

        def sample(self):
            return {'network':self.network(), 'tailscale':self.tails()}

        def action(self, action, target='''):
            state = self.tails()
            if not state['available']:
                return {'error':'Tailscale is unavailable'}
            if action=='connect':
                command = [self.tailscale, 'up']
            elif action=='disconnect':
                command = [self.tailscale, 'down']
            elif action=='exit':
                valid = {p['ip'] for p in state['peers'] if p['exitNode'] and p['online'] and p['ip']}
                if target and target not in valid:
                    return {'error':'That exit node is no longer available'}
                command = [self.tailscale, 'set', '--exit-node='+target]
            else:
                return {'error':'Unknown network action'}
            if not state['operator']:
                # No policy/operator changes: authenticate interactively for this one command.
                return {'terminal':['sudo', *command], 'error':'''}
            result = self.run(command + (['--timeout=10s'] if action=='connect' else []), timeout=15)
            if result.returncode==0:
                return {'error':'''}
            match = re.search(r'https://login\.tailscale\.com/[\w/?=&.%~-]+', result.stdout+'\n'+result.stderr)
            if action=='connect' and match:
                return {'url':match.group(0), 'error':'''}
            return {'error':'Could not change Tailscale; check authorization or try again'}


    def main():
        parser = argparse.ArgumentParser()
        parser.add_argument('--nmcli', default='nmcli')
        parser.add_argument('--tailscale', default='tailscale')
        parser.add_argument('--action', choices=['connect','disconnect','exit'])
        parser.add_argument('--target', default=''')
        args = parser.parse_args()
        backend = Backend(args.nmcli, args.tailscale)
        if args.action:
            print(json.dumps(backend.action(args.action, args.target)), flush=True)
            return
        stop = threading.Event()
        signal.signal(signal.SIGTERM, lambda *_:stop.set())
        signal.signal(signal.SIGINT, lambda *_:stop.set())
        try:
            while not stop.is_set():
                print(json.dumps(backend.sample(), allow_nan=False), flush=True)
                stop.wait(3)
        except BrokenPipeError:
            pass


    if __name__=='__main__':
        main()
  '';

  networkServiceQml = pkgs.writeText "NetworkService.qml" ''
    import QtQuick
    import Quickshell
    import Quickshell.Io

    Scope {
        id: service
        property bool active: false
        property bool requested: false
        property bool busy: false
        property string error: ""
        property string copied: ""
        property var state: ({network:{},tailscale:{available:false,status:"Loading",peers:[]}})
        readonly property alias peersModel: peerRows
        readonly property alias exitsModel: exitRows
        signal commandRequested(var command)
        signal copyRequested(string value)
        ListModel {id:peerRows}
        ListModel {id:exitRows}
        function acceptState(line) {
            try {
                const next=JSON.parse(line);
                if(!next.network || !next.tailscale || !Array.isArray(next.tailscale.peers))return;
                state=next;
                const peers=next.tailscale.peers;
                if(peerRows.count!==peers.length || peers.some((p,i)=>peerRows.get(i).key!==p.key)){
                    peerRows.clear();peers.forEach(p=>peerRows.append({key:p.key}));
                }
                const exits=[{key:"direct"},...peers.filter(p=>p.exitNode)];
                if(exitRows.count!==exits.length || exits.some((p,i)=>exitRows.get(i).key!==p.key)){
                    exitRows.clear();exits.forEach(p=>exitRows.append({key:p.key}));
                }
            } catch(error) {}
        }
        function refresh() {if(active && !requested)requested=true;}
        function manageNetworks() {commandRequested(["${pkgs.networkmanagerapplet}/bin/nm-connection-editor"]);}
        function copy(value, key) {
            if(!value)return;
            copyRequested(value);copied=key;copyReset.restart();
        }
        function action(kind, target) {
            if(busy || !state.tailscale.available || !["connect","disconnect","exit"].includes(kind))return;
            error="";busy=true;
            actionProcess.command=["${pkgs.python3}/bin/python3",Quickshell.shellPath("NetworkBackend.py"),
                "--nmcli","${pkgs.networkmanager}/bin/nmcli","--tailscale","${pkgs.tailscale}/bin/tailscale",
                "--action",kind,"--target",target || ""];
            actionProcess.running=true;
        }
        function acceptAction(line) {
            try {
                const next=JSON.parse(line);
                error=next.error || "";
                if(Array.isArray(next.terminal) && next.terminal.length>1 && next.terminal[0]==="sudo"
                        && next.terminal[1]==="${pkgs.tailscale}/bin/tailscale")
                    commandRequested(["${pkgs.kitty}/bin/kitty","--title","Tailscale authorization","-e",...next.terminal]);
                if(typeof next.url==="string" && /^https:\/\/login\.tailscale\.com\//.test(next.url))Qt.openUrlExternally(next.url);
            } catch(error) {service.error="Could not read the Tailscale response";}
        }
        onActiveChanged:{retry.stop();requested=active;if(!active)copied="";}
        Process {
            id:collector
            running:service.requested
            command:["${pkgs.python3}/bin/python3",Quickshell.shellPath("NetworkBackend.py"),
                "--nmcli","${pkgs.networkmanager}/bin/nmcli","--tailscale","${pkgs.tailscale}/bin/tailscale"]
            stdout:SplitParser {onRead:data=>service.acceptState(data)}
            onExited:{service.requested=false;if(service.active)retry.restart();}
        }
        Process {
            id:actionProcess
            stdout:SplitParser {onRead:data=>service.acceptAction(data)}
            onExited:(code,status)=>{service.busy=false;if(code!==0)service.error="Could not run the Tailscale action";service.refresh();}
        }
        Timer {id:retry;interval:2000;onTriggered:if(service.active)service.requested=true}
        Timer {id:copyReset;interval:1400;onTriggered:service.copied=""}
    }
  '';

  networkDetailsQml = pkgs.writeText "NetworkDetails.qml" ''
    import QtQuick
    import QtQuick.Controls

    Item {
        id: details
        required property var network
        required property var usage
        property Item glassSource: null
        property point glassPosition: Qt.point(0,0)
        property bool active: false
        property bool motionEnabled: true
        property bool choosingExit: false
        readonly property var connection: network.state.network
        readonly property var tail: network.state.tailscale
        // UsageBackend reports physical-interface throughput as download/upload.
        readonly property var down: rate(usage.state.network.download)
        readonly property var up: rate(usage.state.network.upload)
        readonly property var exits: [{key:"direct",name:"Direct connection",ip:"",online:true},
            ...(tail.peers || []).filter(peer=>peer.exitNode)]
        readonly property string exitName: (tail.peers || []).find(peer=>peer.ip===tail.exitNode && peer.ip)?.name || "Direct connection"
        readonly property string tailStatus: network.busy ? "Updating…"
            : ({Running:"Connected",Stopped:"Disconnected",NeedsLogin:"Sign in",NeedsMachineAuth:"Awaiting approval",
                Starting:"Connecting…",Unavailable:"Unavailable",Loading:"Loading…"})[tail.status] || tail.status || "Unavailable"
        width:600;height:420
        function rate(value) {
            if(typeof value!=="number" || !Number.isFinite(value))return {text:"—",unit:"KiB/s"};
            const units=["B/s","KiB/s","MiB/s","GiB/s"];
            let index=0;while(value>=1024 && index<3){value/=1024;index++;}
            return {text:value.toFixed(index===0?0:1),unit:units[index]};
        }
        function total(value) {
            if(typeof value!=="number")return "—";
            const data=rate(value);return data.text+" "+data.unit.replace("/s","");
        }
        function osIcon(name) {
            return ({windows:"",linux:"",macOS:"",darwin:"",android:"",iOS:""})[name] || "󰍹";
        }
        function dismissAt(x,y) {
            const p=exitPicker.mapFromItem(details,x,y);
            if(p.x<0 || p.y<0 || p.x>exitPicker.width || p.y>exitPicker.height)choosingExit=false;
        }
        onActiveChanged:if(!active)choosingExit=false
        TapHandler {onPressedChanged:if(pressed)details.dismissAt(point.position.x,point.position.y)}
        QtObject {
            id:glassContext
            property Item source:details.glassSource
            property Item root:details
            property point origin:details.glassPosition
            property real scale:details.scale
            property int revision:0
            property var layout:[origin.x,origin.y,scale,peers.contentY,exitChoices.contentY,exitPicker.y,exitPicker.height]
            onLayoutChanged:Qt.callLater(()=>{revision++;})
        }

        // Left column: the active connection, live throughput and the editor.
        FrostedSurface {
            x:20;y:20;width:252;height:212;radius:22;glass:glassContext;tint:"#bf222222"
            Text {
                x:16;y:14
                text:details.connection.type==="wifi"?"󰖩":details.connection.name?"󰈀":"󰛳"
                color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:22
            }
            Text {x:48;y:13;width:parent.width-x-50;text:details.connection.name || "No connection";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:13;elide:Text.ElideRight}
            Text {x:48;y:33;width:parent.width-x-50;text:[details.connection.state || "Loading",details.connection.interface].filter(Boolean).join(" · ");color:"#aaaaaa";font.family:"0xProto Nerd Font Mono";font.pixelSize:9;elide:Text.ElideRight}
            MediaButton {
                objectName:"copyNetworkAddress";x:parent.width-44;y:12;width:30;height:30;iconSize:14
                glyph:details.network.copied==="local"?"":"";label:"Copy local address";glass:glassContext
                enabled:!!details.connection.address;motionEnabled:details.motionEnabled
                onClicked:details.network.copy(details.connection.address,"local")
            }
            Rectangle {
                x:10;y:58;width:parent.width-20;height:144;radius:16;color:"#12ffffff"
                Repeater {
                    model:[{label:"IPv4",value:details.connection.address || "—"},
                        {label:"Gateway",value:details.connection.gateway || "—"},
                        {label:"DNS",value:(details.connection.dns || []).join(", ") || "—"},
                        {label:"Link",value:details.connection.speed?details.connection.speed+" Mb/s":details.connection.type==="wifi"?"Wi-Fi":details.connection.type==="ethernet"?"Ethernet":"—"}]
                    delegate:Item {
                        required property int index
                        required property var modelData
                        x:14;y:8+index*32;width:parent.width-28;height:32
                        Text {anchors.verticalCenter:parent.verticalCenter;text:parent.modelData.label;color:"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
                        Text {x:64;anchors.verticalCenter:parent.verticalCenter;width:parent.width-x;text:parent.modelData.value;color:"#eeeeee";font.family:"0xProto Nerd Font Mono";font.pixelSize:10;horizontalAlignment:Text.AlignRight;elide:Text.ElideRight}
                        Rectangle {y:parent.height-1;width:parent.width;height:1;color:"#0effffff";visible:parent.index<3}
                    }
                }
            }
        }
        Row {
            x:20;y:244;spacing:12
            Repeater {
                model:[{glyph:"",label:"Download",name:"networkDownload"},{glyph:"",label:"Upload",name:"networkUpload"}]
                delegate:FrostedSurface {
                    id:rateCard
                    required property int index
                    required property var modelData
                    readonly property var rateData:index===0?details.down:details.up
                    width:120;height:92;radius:20;glass:glassContext;tint:"#bf222222"
                    Accessible.name:modelData.label
                    Text {x:14;y:13;text:rateCard.modelData.glyph+"  "+rateCard.modelData.label;color:"#aaaaaa";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
                    UsageValue {objectName:rateCard.modelData.name;x:14;y:32;text:rateCard.rateData.text;unit:rateCard.rateData.unit;fontSize:22;slots:4;active:details.active;motionEnabled:details.motionEnabled}
                    Text {
                        x:14;y:parent.height-height-12;width:parent.width-28
                        text:details.total(rateCard.index===0?details.connection.received:details.connection.sent)+" total"
                        color:"#888888";font.family:"0xProto Nerd Font Mono";font.pixelSize:9;elide:Text.ElideRight
                    }
                }
            }
        }
        MediaButton {
            objectName:"manageNetworks";x:20;y:348;width:252;height:44;glass:glassContext;label:"Manage networks";motionEnabled:details.motionEnabled
            onClicked:details.network.manageNetworks()
            contentItem:Item {
                Text {anchors.centerIn:parent;text:"󰒓  Manage networks";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:12}
            }
        }

        // Right column: Tailscale, its peers and the exit node picker.
        Item {
            id:tailscaleCard;x:292;y:20;width:288;height:380
            FrostedSurface {anchors.fill:parent;radius:24;glass:glassContext;tint:"#bf222222"}
            Text {x:16;y:15;text:"";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:20}
            Text {x:46;y:12;text:"Tailscale";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:13}
            Rectangle {x:47;y:36;width:6;height:6;radius:3;color:details.tail.running?"#9acb92":"#666666"}
            Text {x:59;y:31;width:parent.width-x-60;text:details.tailStatus;color:"#aaaaaa";font.family:"0xProto Nerd Font Mono";font.pixelSize:9;elide:Text.ElideRight}
            MediaButton {
                id:tailToggle;objectName:"toggleTailscale";x:parent.width-52;y:12;width:36;height:36;iconSize:18
                glass:glassContext;glyph:details.network.busy?"":"";selected:!!details.tail.running
                label:details.tail.running?"Disconnect Tailscale":"Connect Tailscale"
                enabled:!!details.tail.available && !details.network.busy;motionEnabled:details.motionEnabled
                onClicked:{details.choosingExit=false;details.network.action(details.tail.running?"disconnect":"connect","");}
            }
            Item {
                id:tailBody
                width:parent.width;height:parent.height
                opacity:1-exitPicker.progress;enabled:exitPicker.progress===0
                Rectangle {
                    x:12;y:60;width:parent.width-24;height:56;radius:16;color:"#12ffffff"
                    Text {x:14;y:10;width:parent.width-x-50;text:details.tail.name || "This device";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:12;elide:Text.ElideRight}
                    Text {x:14;y:30;text:details.tail.ip || "—";color:"#bbbbbb";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
                    MediaButton {
                        objectName:"copyTailscaleAddress";x:parent.width-42;y:13;width:30;height:30;iconSize:14
                        glass:glassContext;glyph:details.network.copied==="self"?"":"";label:"Copy Tailscale address"
                        enabled:!!details.tail.ip;motionEnabled:details.motionEnabled;onClicked:details.network.copy(details.tail.ip,"self")
                    }
                }
                Text {x:16;y:130;text:"Devices";color:"#aaaaaa";font.family:"0xProto Nerd Font Mono";font.pixelSize:10}
                Text {x:134;y:130;width:parent.width-x-16;text:(details.tail.peers || []).filter(p=>p.online).length+" online";color:"#888888";font.family:"0xProto Nerd Font Mono";font.pixelSize:10;horizontalAlignment:Text.AlignRight}
                ListView {
                    // Exactly three rows tall, so a scrolled list never cuts a peer in half.
                    id:peers;objectName:"tailscalePeers";x:12;y:150;width:parent.width-36;height:146;spacing:4;clip:true
                    model:details.network.peersModel
                    delegate:MediaButton {
                        id:peerButton
                        required property int index
                        readonly property var peer:details.tail.peers[index] || ({})
                        objectName:"tailPeer-"+(peer.key || "");width:peers.width;height:46;glass:glassContext
                        label:"Copy "+peer.name+" address";motionEnabled:details.motionEnabled;enabled:!!peer.ip
                        onClicked:details.network.copy(peer.ip,peer.key)
                        contentItem:Item {
                            Text {x:14;anchors.verticalCenter:parent.verticalCenter;text:details.network.copied===peerButton.peer.key?"":details.osIcon(peerButton.peer.os);color:peerButton.peer.online?"white":"#666666";font.family:"0xProto Nerd Font Mono";font.pixelSize:18}
                            Text {x:44;y:8;width:parent.width-x-28;text:peerButton.peer.name || "";color:peerButton.peer.online?"white":"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:11;elide:Text.ElideRight}
                            Text {x:44;y:25;width:parent.width-x-28;text:peerButton.peer.online?peerButton.peer.ip || "":"Offline";color:"#888888";font.family:"0xProto Nerd Font Mono";font.pixelSize:9;elide:Text.ElideRight}
                            Rectangle {anchors.right:parent.right;anchors.rightMargin:16;anchors.verticalCenter:parent.verticalCenter;width:6;height:6;radius:3;color:peerButton.peer.online?"#9acb92":"#555555"}
                        }
                    }
                    ScrollBar.vertical:PlaylistScrollBar {parent:peers.parent;anchors.top:peers.top;anchors.bottom:peers.bottom;anchors.left:peers.right;anchors.leftMargin:6}
                }
                Text {x:16;y:212;width:parent.width-32;visible:peers.count===0;text:details.tail.running?"No other devices":"Not connected";color:"#888888";font.family:"0xProto Nerd Font Mono";font.pixelSize:11;horizontalAlignment:Text.AlignHCenter}
                Text {x:16;y:308;text:"Exit node";color:"#999999";font.family:"0xProto Nerd Font Mono";font.pixelSize:9}
                MediaButton {
                    objectName:"chooseExitNode";x:14;y:326;width:parent.width-28;height:38;glass:glassContext
                    label:"Choose exit node";motionEnabled:details.motionEnabled
                    visible:exitPicker.progress===0;enabled:!!details.tail.running && !details.network.busy
                    onClicked:details.choosingExit=true
                    contentItem:Item {
                        Text {x:14;anchors.verticalCenter:parent.verticalCenter;width:parent.width-44;text:details.exitName;color:"white";opacity:parent.parent.enabled?1:0.4;font.family:"0xProto Nerd Font Mono";font.pixelSize:11;elide:Text.ElideRight}
                        Text {anchors.right:parent.right;anchors.rightMargin:14;anchors.verticalCenter:parent.verticalCenter;text:"";color:"white";opacity:parent.parent.enabled?1:0.4;font.family:"0xProto Nerd Font Mono";font.pixelSize:13}
                    }
                }
            }
            MediaMorphPanel {
                id:exitPicker;objectName:"exitNodePicker";x:14;y:326-(fullHeight-38)*progress
                compactWidth:tailscaleCard.width-28;fullWidth:compactWidth;fullHeight:310;glass:glassContext
                opened:details.choosingExit;motionEnabled:details.motionEnabled
                Item {
                    anchors.fill:parent;opacity:exitPicker.progress;enabled:exitPicker.opened
                    Text {x:16;y:16;text:"Exit node";color:"#aaaaaa";font.family:"0xProto Nerd Font Mono";font.pixelSize:12}
                    ListView {
                        id:exitChoices;objectName:"exitNodeChoices";x:8;y:44;width:parent.width-32;height:parent.height-y-12;spacing:4;clip:true
                        model:details.network.exitsModel
                        delegate:MediaButton {
                            id:exitButton
                            required property int index
                            readonly property var modelData:details.exits[index] || ({})
                            width:exitChoices.width;height:46;glass:glassContext
                            label:"Use "+modelData.name;selected:(modelData.ip || "")===(details.tail.exitNode || "")
                            motionEnabled:details.motionEnabled;enabled:modelData.online && !details.network.busy
                            onClicked:{details.choosingExit=false;details.network.action("exit",modelData.ip);}
                            contentItem:Item {
                                Text {x:14;anchors.verticalCenter:parent.verticalCenter;width:parent.width-48;text:exitButton.modelData.name;color:exitButton.enabled?"white":"#777777";font.family:"0xProto Nerd Font Mono";font.pixelSize:11;elide:Text.ElideRight}
                                Text {anchors.right:parent.right;anchors.rightMargin:14;anchors.verticalCenter:parent.verticalCenter;visible:exitButton.selected;text:"";color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:12}
                            }
                        }
                        ScrollBar.vertical:PlaylistScrollBar {parent:exitChoices.parent;anchors.top:exitChoices.top;anchors.bottom:exitChoices.bottom;anchors.left:exitChoices.right;anchors.leftMargin:6}
                    }
                }
            }
        }
        Text {x:20;y:402;width:560;height:14;visible:details.network.error!=="";text:details.network.error;color:"#c4aaaa";font.family:"0xProto Nerd Font Mono";font.pixelSize:9;elide:Text.ElideRight}
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
            windows = clients.filter(c => c && c.mapped !== false && addressValid(c.address)).map(c => {
                const key=String(c.stableId ?? c.address)+":"+String(c.pid);
                const prior = old.find(w => w.key === key);
                const entry = DesktopEntries.heuristicLookup(c.class || c.initialClass || "");
                return {address:c.address,pid:c.pid || 0,key:key,
                    className:c.class || c.initialClass || "", title:c.title || c.class || "",
                    appName:entry?.name || c.class || c.initialClass || "Application",
                    workspace:c.workspace?.id ?? -1,workspaceName:c.workspace?.name || "",
                    pinned:c.pinned === true,born:prior?.born ?? now,
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
                dispatchRequested('hl.dsp.focus({window="address:'+address+'"})');
        }
        function closeWindow(address = selectedAddress) {
            if (addressValid(address) && windows.some(w => w.address === address))
                dispatchRequested('hl.dsp.window.close({window="address:'+address+'"})');
        }
        onClientsChanged: Qt.callLater(refresh)
        onFocusedChanged: Qt.callLater(refresh)
        onWorkspaceChanged: Qt.callLater(refresh)
        onActiveChanged: sync()
        Connections {target:DesktopEntries.applications;function onValuesChanged(){Qt.callLater(service.refresh);}}
        Connections {
            target:Hyprland
            function onRawEvent(event) {
                if (["activewindowv2","workspacev2","openwindow","closewindow","movewindowv2",
                    "windowtitlev2","pin","activespecial","activespecialv2"].includes(event.name))
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

  appWindowButtonQml = pkgs.writeText "AppWindowButton.qml" ''
    import QtQuick
    import QtQuick.Controls
    import Quickshell
    import Quickshell.Widgets

    AbstractButton {
        id: button
        required property var windowData
        property url iconSource: ""
        property QtObject glass: null
        property bool compact: false
        property bool showWorkspace: true
        property bool selected: false
        property bool motionEnabled: true
        readonly property bool highlighted: hovered || visualFocus
        property real hoverProgress: highlighted ? 1 : 0
        Behavior on hoverProgress {NumberAnimation {duration:button.motionEnabled?(button.highlighted?300:220):0;easing.type:Easing.OutCubic}}
        readonly property color iconTint: {
            let chosen=Qt.rgba(21/255,21/255,21/255,1),score=0;
            const colors=!iconSource ? [] : String(iconSource).startsWith("image:") ? providerPalette.colors : palette.colors;
            for (const color of colors) {
                const saturation=Math.max(color.r,color.g,color.b)-Math.min(color.r,color.g,color.b);
                if (color.a>0.5 && saturation>score) {score=saturation;chosen=color;}
            }
            const mix=0.18,base=21/255;
            return Qt.rgba(base*(1-mix)+chosen.r*mix,base*(1-mix)+chosen.g*mix,base*(1-mix)+chosen.b*mix,0.75);
        }
        readonly property color neutralTint: selected ? "#bf303030" : "#bf222222"
        readonly property color trailingTint: Qt.rgba(
            neutralTint.r+(iconTint.r-neutralTint.r)*hoverProgress,
            neutralTint.g+(iconTint.g-neutralTint.g)*hoverProgress,
            neutralTint.b+(iconTint.b-neutralTint.b)*hoverProgress,0.75)
        readonly property string workspaceLabel: windowData.workspace > 0 ? String(windowData.workspace)
            : (windowData.workspaceName || "").replace(/^special:/, "") || "S"
        signal closeRequested()
        implicitWidth: compact ? 66 : 224
        implicitHeight: compact ? 66 : 96
        padding: 0
        hoverEnabled: true
        Accessible.name: (windowData.appName || windowData.className) + ", " + windowData.title
            + (showWorkspace ? ", workspace " + workspaceLabel : "")
        ToolTip.visible: hovered
        ToolTip.delay: 700
        ToolTip.text: windowData.title + (showWorkspace ? " · " + workspaceLabel : "")
        // Each tile owns its palette and rounded surface; neighboring icon
        // colors never enter this tile's gradient or its hover transition.
        ColorQuantizer {
            id:palette
            source:String(button.iconSource).startsWith("image:") ? "" : button.iconSource
            depth:3;rescaleSize:48
        }
        // ColorQuantizer accepts local files only. Tray pixmaps and theme
        // icons use Qt image providers, so sample those once per icon update
        // in a private 48px canvas, without writing temporary raster files.
        Canvas {
            id:providerPalette
            width:48;height:48;opacity:0
            property var colors:[]
            property string source:String(button.iconSource).startsWith("image:") ? String(button.iconSource) : ""
            property string loadedSource:""
            function load() {
                colors=[];
                if(!available)return;
                if(loadedSource)unloadImage(loadedSource);
                loadedSource=source;
                if(source)loadImage(source);
            }
            onSourceChanged:load()
            onAvailableChanged:if(available)load()
            onImageLoaded:requestPaint()
            onPaint: {
                if(!source || !isImageLoaded(source))return;
                const ctx=getContext("2d");ctx.clearRect(0,0,width,height);
                ctx.drawImage(source,0,0,width,height);
                const pixels=ctx.getImageData(0,0,width,height).data,buckets={};
                for(let i=0;i<pixels.length;i+=4) {
                    if(pixels[i+3]<128)continue;
                    const r=pixels[i],g=pixels[i+1],b=pixels[i+2];
                    const key=(r>>5)*64+(g>>5)*8+(b>>5);
                    if(!buckets[key])buckets[key]={count:0,r:0,g:0,b:0};
                    const bucket=buckets[key];bucket.count++;bucket.r+=r;bucket.g+=g;bucket.b+=b;
                }
                colors=Object.values(buckets).sort((a,b)=>b.count-a.count).slice(0,8)
                    .map(bucket=>Qt.rgba(bucket.r/bucket.count/255,bucket.g/bucket.count/255,bucket.b/bucket.count/255,1));
            }
        }
        background: FrostedSurface {
            id: tileSurface
            radius: 22
            glass: button.glass
            tintGradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {position:0;color:button.iconTint}
                GradientStop {position:1;color:button.trailingTint}
            }
            HoverOutline {
                anchors.fill: parent
                cornerRadius: tileSurface.radius
                hovered: button.highlighted
                active: button.enabled
                motionEnabled: button.motionEnabled
            }
        }
        contentItem: Item {
            Item {
                id: iconFrame
                x: button.compact ? (parent.width-width)/2 : 14
                y: (parent.height-height)/2
                width: button.compact ? 38 : 64
                height: width
                Item {
                    objectName: "appIconTransform"
                    anchors.fill: parent
                    scale: button.highlighted ? 1.12 : 1
                    Behavior on scale {NumberAnimation {duration:button.motionEnabled?180:0;easing.type:Easing.OutCubic}}
                    Image {
                        id: appIcon
                        anchors.fill: parent
                        source: button.iconSource
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true;smooth: true;mipmap: true
                        sourceSize: Qt.size(Math.ceil(width*1.12*Screen.devicePixelRatio), Math.ceil(height*1.12*Screen.devicePixelRatio))
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: appIcon.status !== Image.Ready
                        text: "";color: "white"
                        font.family: "0xProto Nerd Font Mono"
                        font.pixelSize: button.compact ? 28 : 46
                    }
                }
                FrostedSurface {
                    objectName: "appWorkspaceBadge"
                    visible: button.showWorkspace
                    x: parent.width - width + 3;y: parent.height - height + 3
                    width: button.compact ? 22 : 28;height: width
                    radius: width/2
                    glass: button.glass;tint: "#df151515"
                    WorkspaceBadge {
                        anchors.centerIn: parent
                        height: parent.height
                        expanded: true;gap: 0;minimumIconWidth: 16
                        workspaceId: button.windowData.workspace
                        motionEnabled: button.motionEnabled
                    }
                }
            }
            Column {
                x: 92;anchors.verticalCenter: parent.verticalCenter;width: parent.width-x-16
                visible: !button.compact
                spacing: 4
                Text {
                    width: parent.width
                    text: button.windowData.appName || button.windowData.className
                    color: "white";font.family: "0xProto Nerd Font Mono";font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: button.windowData.title || ""
                    color: "#aaaaaa";font.family: "0xProto Nerd Font Mono";font.pixelSize: 9
                    wrapMode: Text.Wrap;maximumLineCount: 2;elide: Text.ElideRight
                }
            }
        }
        // The normal button retains left-click and keyboard activation. Only
        // middle clicks are intercepted here, including in the compact rail.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.MiddleButton
            onClicked: button.closeRequested()
        }
        HoverHandler {cursorShape: Qt.PointingHandCursor}
    }
  '';

  appTrayButtonQml = pkgs.writeText "AppTrayButton.qml" ''
    import QtQuick
    import Quickshell

    AppWindowButton {
        id: button
        required property var trayItem
        property bool active: true
        property bool closePending: false
        compact: true
        showWorkspace: false
        windowData: ({appName:trayItem.title || trayItem.id || "Application",
            title:trayItem.tooltipTitle || trayItem.title || trayItem.id || "Application",workspace:0})
        iconSource: {
            const source=trayItem.icon || "";
            if(!source.startsWith("image://icon/"))return source;
            // Steam and other apps publish icons outside the desktop theme.
            if(source.includes("?path="))return source;
            const name=decodeURIComponent(source.slice("image://icon/".length).split("?")[0]);
            return Quickshell.iconPath(name,true);
        }

        function showMenu() {
            if (!active || !trayItem.hasMenu) return;
            const position=mapToItem(null,width,0);
            trayItem.display(button.QsWindow.window,Math.round(position.x),Math.round(position.y));
        }
        function quitEntry(entries) {
            const names=[trayItem.title,trayItem.id].filter(Boolean).map(name=>name.toLowerCase());
            return entries.find(entry=>{
                const label=entry.text.replace(/&/g,"").split("\t")[0].replace(/…|\.\.\./g,"").trim().toLowerCase();
                return entry.enabled && !entry.isSeparator && !entry.hasChildren
                    && (label==="quit" || label==="exit" || names.some(name=>label==="quit "+name || label==="exit "+name));
            });
        }
        function attemptClose() {
            if (!closePending || !active) return;
            const entry=quitEntry(menu.children.values);
            if (entry) {closePending=false;closeTimeout.stop();entry.triggered();}
        }
        onClicked: {
            if (!active) return;
            if (trayItem.onlyMenu) showMenu();
            else trayItem.activate();
        }
        onCloseRequested: {
            // StatusNotifier has no universal close method. Use the app's
            // explicit Quit/Exit menu action, never secondaryActivate or kill.
            if (!active || !trayItem.hasMenu) return;
            closePending=true;closeTimeout.restart();attemptClose();
        }
        onActiveChanged: if(!active) {closePending=false;closeTimeout.stop();}
        QsMenuOpener {
            id: menu
            menu: button.active && button.trayItem.hasMenu ? button.trayItem.menu : null
            onChildrenChanged: button.attemptClose()
        }
        Timer {
            id: closeTimeout
            interval: 500
            onTriggered: {
                button.attemptClose();
                if (button.closePending) {button.closePending=false;button.showMenu();}
            }
        }
        MouseArea {anchors.fill:parent;acceptedButtons:Qt.RightButton;onClicked:button.showMenu()}
    }
  '';

  appsDetailsQml = pkgs.writeText "AppsDetails.qml" ''
    import QtQuick
    import QtQuick.Controls

    Item {
        id: details
        required property var window
        property var trayItems: []
        property Item glassSource: null
        property point glassPosition: Qt.point(0,0)
        property bool active: false
        property bool motionEnabled: true
        readonly property alias windowsModel: windowRows
        readonly property int trayCount: trayButtons.count
        readonly property bool hasTray: trayCount>0
        width: 600;height: 420

        // Update roles in place: focus, titles and icon refreshes must not reset
        // a hovered tile, its animation, or either scroll position.
        function reconcile(model, rows) {
            const keys = rows.map(row=>row.key);
            for (let i=model.count-1;i>=0;--i)
                if (!keys.includes(model.get(i).key)) model.remove(i);
            rows.forEach((row,index)=>{
                let found=index;
                while (found<model.count && model.get(found).key!==row.key) found++;
                if (found===model.count) model.insert(index,row);
                else {
                    if (found!==index) model.move(found,index,1);
                    for (const role of Object.keys(row))
                        if (model.get(index)[role]!==row[role]) model.setProperty(index,role,row[role]);
                }
            });
        }
        function refresh() {
            const rows = window.windows.map(w=>({key:w.key,address:w.address,title:w.title,
                appName:w.appName || w.className,className:w.className,workspace:w.workspace,
                workspaceName:w.workspaceName || ""}));
            reconcile(windowRows,rows);
        }
        Component.onCompleted: if(active) refresh()
        onWindowChanged: if(active) refresh()
        onActiveChanged: if(active) refresh()
        Connections {
            target: details.window
            enabled: details.active
            function onWindowsChanged() {details.refresh();}
        }
        ListModel {id:windowRows}
        QtObject {
            id: glassContext
            property Item source: details.glassSource
            property Item root: details
            property point origin: details.glassPosition
            property real scale: details.scale
            property int revision: 0
            property var layout: [origin.x,origin.y,scale,apps.contentY,trayApps.contentY,apps.width]
            onLayoutChanged: Qt.callLater(()=>{revision++;})
        }
        Flickable {
            id: apps
            objectName: "windowApps"
            x: 20;y: 20
            // Without tray registrations the window grid takes the whole panel.
            width: details.hasTray ? 456 : 566;height: 380
            contentWidth: width
            contentHeight: appsGrid.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            ScrollBar.vertical: PlaylistScrollBar {width:6}
            Grid {
                id: appsGrid
                width: apps.width-12
                columns: 2;spacing: 12
                Repeater {
                    model: windowRows
                    delegate: AppWindowButton {
                        required property var model
                        objectName: "app-"+model.address
                        width: (appsGrid.width-appsGrid.spacing)/2
                        windowData: model
                        iconSource: details.window.icons[model.key] || ""
                        selected: details.window.selectedAddress===model.address
                        glass: glassContext;motionEnabled: details.motionEnabled
                        onClicked: details.window.focusWindow(model.address)
                        onCloseRequested: details.window.closeWindow(model.address)
                    }
                }
            }
        }
        FrostedSurface {
            x: 20;y: 20;width: details.hasTray ? 456 : 560;height: 380;radius: 24
            visible: windowRows.count===0
            glass: glassContext;tint: "#bf222222"
            Column {
                anchors.centerIn: parent;spacing: 10
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "";color: "#777777"
                    font.family: "0xProto Nerd Font Mono";font.pixelSize: 34
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No open windows"
                    color: "#aaaaaa";font.family: "0xProto Nerd Font Mono";font.pixelSize: 12
                }
            }
        }
        FrostedSurface {
            id: trayCard
            x: 488;y: 20;width: 92;height: 380;radius: 24
            visible: details.hasTray
            glass: glassContext;tint: "#bf222222"
        }
        Flickable {
            id: trayApps
            objectName: "trayApps"
            x: trayCard.x+13;y: trayCard.y+13;width: 76;height: trayCard.height-26
            visible: details.hasTray
            contentWidth: width
            contentHeight: trayColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            ScrollBar.vertical: PlaylistScrollBar {width:6}
            Column {
                id: trayColumn
                width: trayApps.width-10;spacing: 10
                Repeater {
                    id: trayButtons
                    model: details.trayItems
                    delegate: AppTrayButton {
                        required property var modelData
                        objectName: "tray-app-"+modelData.id
                        trayItem: modelData
                        glass: glassContext;motionEnabled: details.motionEnabled
                        active: details.active
                    }
                }
            }
        }
    }
  '';

  aiBackendPython = pkgs.writeText "AiBackend.py" ''
    """AI usage limits and the T3 Code server for the Quickshell AI panel.

    Without --action, print one JSON state line and exit. Claude limits come from
    the same OAuth usage endpoint Claude Code's /usage uses; Codex limits are read
    from the rate-limit snapshots Codex writes into its local session logs. The
    Claude OAuth token is only ever sent to api.anthropic.com and is never
    refreshed or rewritten here.
    """
    import argparse
    import datetime
    import json
    import os
    from pathlib import Path
    import re
    import shutil
    import signal
    import subprocess
    import sys
    import time
    import urllib.error
    import urllib.request

    UNIT = 'quickshell-t3code'
    CLAUDE_URL = 'https://api.anthropic.com/api/oauth/usage'
    CLAUDE_CACHE_SECONDS = 120
    CODEX_TAIL_BYTES = 4 * 1024 * 1024


    def home():
        return Path(os.environ.get('HOME') or Path.home())


    def expand(value, default):
        value = (value or ''').strip()
        if not value:
            return default
        if value == '~':
            return home()
        if value.startswith('~/'):
            return home() / value[2:]
        return Path(value).resolve()


    def cache_path():
        runtime = os.environ.get('XDG_RUNTIME_DIR') or '/tmp'
        return Path(runtime) / 'quickshell-ai-claude.json'


    def iso_ms(value):
        if not isinstance(value, str) or not value:
            return None
        try:
            return int(datetime.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp() * 1000)
        except ValueError:
            return None


    def bounded(value):
        if not isinstance(value, (int, float)) or value != value:
            return None
        return max(0.0, min(100.0, float(value)))


    def window(label, used, resets_at, now_ms):
        """One limit window, reported as the share still remaining (100 = untouched)."""
        # A window whose reset time has already passed has rolled over to full.
        if resets_at is not None and resets_at <= now_ms:
            return {'label': label, 'remaining': 100.0, 'resetsAt': None}
        used = bounded(used)
        return {'label': label, 'remaining': None if used is None else 100.0 - used, 'resetsAt': resets_at}


    def installed(name, extra=()):
        path = os.environ.get('PATH', ''')
        candidates = [path, str(home() / '.nix-profile/bin'), '/etc/profiles/per-user/'
            + os.environ.get('USER', ''') + '/bin', '/run/current-system/sw/bin', str(home() / '.local/bin'), *extra]
        return shutil.which(name, path=os.pathsep.join(c for c in candidates if c)) is not None


    # --- Claude -----------------------------------------------------------------

    def claude_usage(payload, now_ms):
        windows = []
        for key, label in (('five_hour', '5-hour'), ('seven_day', 'Weekly')):
            entry = payload.get(key)
            if isinstance(entry, dict):
                windows.append(window(label, entry.get('utilization'), iso_ms(entry.get('resets_at')), now_ms))
        return windows


    def claude_state(now, fetch=None, credentials=None, cache=None):
        """Return the Claude provider entry, using a short cache to spare the API."""
        config = expand(os.environ.get('CLAUDE_CONFIG_DIR'), home() / '.claude')
        credentials = credentials or config / '.credentials.json'
        cache = cache or cache_path()
        entry = {'id': 'claude', 'name': 'Claude', 'plan': ''', 'windows': [], 'error': ''', 'updatedAt': None}
        try:
            oauth = json.loads(Path(credentials).read_text()).get('claudeAiOauth') or {}
        except (OSError, ValueError):
            entry['error'] = 'Sign in to Claude Code'
            return entry
        entry['plan'] = str(oauth.get('subscriptionType') or ''').capitalize()
        token = oauth.get('accessToken')
        if not token:
            entry['error'] = 'Sign in to Claude Code'
            return entry
        cached = None
        try:
            cached = json.loads(Path(cache).read_text())
        except (OSError, ValueError):
            pass
        now_ms = int(now * 1000)
        if cached and isinstance(cached.get('payload'), dict) and now - cached.get('fetched', 0) < CLAUDE_CACHE_SECONDS:
            entry['windows'] = claude_usage(cached['payload'], now_ms)
            entry['updatedAt'] = int(cached['fetched'] * 1000)
            return entry
        expires = oauth.get('expiresAt')
        if isinstance(expires, (int, float)) and expires <= now_ms:
            entry['error'] = 'Open Claude Code to refresh sign-in'
        else:
            try:
                payload = (fetch or fetch_claude)(token)
                if not isinstance(payload, dict):
                    raise ValueError('unexpected response')
                Path(cache).write_text(json.dumps({'fetched': now, 'payload': payload}))
                os.chmod(cache, 0o600)
                entry['windows'] = claude_usage(payload, now_ms)
                entry['updatedAt'] = now_ms
                return entry
            except urllib.error.HTTPError as error:
                entry['error'] = 'Open Claude Code to refresh sign-in' if error.code in (401, 403) \
                    else 'Usage is rate limited' if error.code == 429 else 'Usage unavailable'
            except (OSError, ValueError):
                entry['error'] = 'Usage unavailable'
        # Keep showing the last known numbers next to the error.
        if cached and isinstance(cached.get('payload'), dict):
            entry['windows'] = claude_usage(cached['payload'], now_ms)
            entry['updatedAt'] = int(cached.get('fetched', 0) * 1000)
        return entry


    def fetch_claude(token):
        request = urllib.request.Request(CLAUDE_URL, headers={
            'Authorization': 'Bearer ' + token,
            'anthropic-beta': 'oauth-2025-04-20',
            'Content-Type': 'application/json',
            'User-Agent': 'quickshell-ai-panel',
        })
        with urllib.request.urlopen(request, timeout=8) as response:
            return json.loads(response.read().decode())


    # --- Codex ------------------------------------------------------------------

    def codex_snapshot(path):
        """Newest rate-limit snapshot in one rollout file, or None."""
        try:
            with open(path, 'rb') as handle:
                handle.seek(0, os.SEEK_END)
                size = handle.tell()
                handle.seek(max(0, size - CODEX_TAIL_BYTES))
                data = handle.read()
        except OSError:
            return None
        for line in reversed(data.split(b'\n')):
            if b'"rate_limits"' not in line:
                continue
            try:
                event = json.loads(line)
            except ValueError:
                continue
            limits = (event.get('payload') or {}).get('rate_limits')
            if isinstance(limits, dict) and (limits.get('primary') or limits.get('secondary')):
                return {'limits': limits, 'timestamp': iso_ms(event.get('timestamp'))}
        return None


    def codex_state(now, root=None, scan=12):
        root = Path(root or expand(os.environ.get('CODEX_HOME'), home() / '.codex')) / 'sessions'
        entry = {'id': 'codex', 'name': 'Codex', 'plan': ''', 'windows': [], 'error': ''', 'updatedAt': None}
        try:
            files = sorted(root.rglob('rollout-*.jsonl'), key=lambda p: p.stat().st_mtime, reverse=True)
        except OSError:
            files = []
        snapshot = None
        for path in files[:scan]:
            snapshot = codex_snapshot(path)
            if snapshot:
                break
        if not snapshot:
            entry['error'] = 'Run Codex once to load limits'
            return entry
        limits, now_ms = snapshot['limits'], int(now * 1000)
        entry['plan'] = str(limits.get('plan_type') or ''').capitalize()
        entry['updatedAt'] = snapshot['timestamp']
        found = []
        for key in ('primary', 'secondary'):
            value = limits.get(key)
            if not isinstance(value, dict):
                continue
            minutes = value.get('window_minutes') or 0
            label = '5-hour' if minutes and minutes <= 360 else 'Weekly' if minutes >= 7 * 1440 - 60 else \
                (str(round(minutes / 60)) + '-hour' if minutes < 1440 else str(round(minutes / 1440)) + '-day')
            resets = value.get('resets_at')
            found.append((minutes, window(label, value.get('used_percent'),
                int(resets * 1000) if isinstance(resets, (int, float)) else None, now_ms)))
        entry['windows'] = [item for _, item in sorted(found, key=lambda pair: pair[0])]
        return entry


    # --- T3 Code ----------------------------------------------------------------

    def t3_home():
        return expand(os.environ.get('T3CODE_HOME'), home() / '.t3')


    def pid_alive(pid):
        if not isinstance(pid, int) or pid <= 0:
            return False
        try:
            os.kill(pid, 0)
            return True
        except PermissionError:
            return True
        except OSError:
            return False


    def t3_runtime(base=None):
        try:
            runtime = json.loads((Path(base or t3_home()) / 'userdata' / 'server-runtime.json').read_text())
        except (OSError, ValueError):
            return None
        if not isinstance(runtime, dict) or not pid_alive(runtime.get('pid')):
            return None
        return runtime


    def unit_state(systemctl):
        try:
            result = subprocess.run([systemctl, '--user', 'is-active', UNIT + '.service'],
                capture_output=True, text=True, timeout=5)
            return result.stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return 'unknown'


    def t3_state(systemctl, base=None):
        runtime = t3_runtime(base)
        unit = unit_state(systemctl)
        if runtime:
            return {'state': 'running', 'origin': runtime.get('origin') or ''', 'port': runtime.get('port'),
                'version': runtime.get('serverVersion') or ''', 'managed': unit == 'active'}
        if unit in ('active', 'activating', 'reloading'):
            return {'state': 'starting', 'origin': ''', 'port': None, 'version': ''', 'managed': True}
        return {'state': 'stopped', 'origin': ''', 'port': None, 'version': ''', 'managed': False}


    def t3_command(args, runtime=None):
        """Prefer the exact runtime binary the live server uses; otherwise npx."""
        version = (runtime or {}).get('serverVersion')
        if version and re.fullmatch(r'[0-9A-Za-z.+-]+', version):
            binary = t3_home() / 'runtime' / 'versions' / version / 't3'
            if os.access(binary, os.X_OK):
                return [str(binary)]
        return [args.steam_run, args.npx, '--yes', 't3@nightly']


    def reachable(origin):
        try:
            with urllib.request.urlopen(origin, timeout=2):
                return True
        except urllib.error.HTTPError:
            return True
        except (OSError, ValueError):
            return False


    def pair(args, runtime):
        result = subprocess.run([*t3_command(args, runtime), 'pair', '--ttl', '5m', '--label', 'Quickshell'],
            capture_output=True, text=True, timeout=120, cwd=str(home()))
        match = re.search(r'Pairing URL:\s*(https?://\S+)', result.stdout)
        if not match:
            raise RuntimeError('T3 did not return a pairing link')
        return match.group(1)


    def start(args):
        if not t3_runtime():
            if unit_state(args.systemctl) not in ('active', 'activating'):
                path = os.path.dirname(args.npx) + os.pathsep + os.environ.get('PATH', ''')
                subprocess.run([args.systemd_run, '--user', '--unit', UNIT, '--collect', '--quiet',
                    '--description', 'T3 Code server (Quickshell)', '--working-directory', str(home()),
                    '--setenv', 'PATH=' + path, args.steam_run, args.npx, '--yes', 't3@nightly', 'serve'],
                    check=True, capture_output=True, timeout=20)
            deadline = time.monotonic() + args.timeout
            while time.monotonic() < deadline:
                runtime = t3_runtime()
                if runtime and reachable(runtime.get('origin') or '''):
                    break
                if unit_state(args.systemctl) in ('failed', 'inactive') and not t3_runtime():
                    raise RuntimeError('T3 stopped while starting (journalctl --user -u ' + UNIT + ')')
                time.sleep(0.5)
            else:
                raise RuntimeError('T3 did not start in time')
        return open_url(args)


    def open_url(args):
        runtime = t3_runtime()
        if not runtime:
            raise RuntimeError('T3 is not running')
        try:
            return pair(args, runtime)
        except (OSError, subprocess.SubprocessError, RuntimeError):
            # A browser that already paired keeps its session; the origin still works.
            if runtime.get('origin'):
                return runtime['origin']
            raise


    def stop(args):
        if unit_state(args.systemctl) in ('active', 'activating'):
            subprocess.run([args.systemctl, '--user', 'stop', UNIT + '.service'], capture_output=True, timeout=30)
        runtime = t3_runtime()
        if runtime:
            pid = runtime['pid']
            try:
                command = Path('/proc/' + str(pid) + '/cmdline').read_bytes().split(b'\0')
            except OSError:
                command = []
            # Only signal an actual `t3 serve` process, never an unrelated reused pid.
            if any(part.endswith(b't3') or part.endswith(b't3.mjs') for part in command) and b'serve' in command:
                os.kill(pid, signal.SIGTERM)
                deadline = time.monotonic() + 15
                while pid_alive(pid) and time.monotonic() < deadline:
                    time.sleep(0.25)
                if pid_alive(pid):
                    os.kill(pid, signal.SIGKILL)
            else:
                raise RuntimeError('Refusing to stop an unrecognised process')
        return '''


    def main():
        parser = argparse.ArgumentParser()
        parser.add_argument('--systemctl', default='systemctl')
        parser.add_argument('--systemd-run', default='systemd-run')
        parser.add_argument('--steam-run', default='steam-run')
        parser.add_argument('--npx', default='npx')
        parser.add_argument('--timeout', type=float, default=180)
        parser.add_argument('--action', choices=('start', 'stop', 'open'))
        args = parser.parse_args()
        if args.action:
            try:
                url = {'start': start, 'stop': stop, 'open': open_url}[args.action](args)
                print(json.dumps({'ok': True, 'url': url, 'error': '''}), flush=True)
            except (OSError, subprocess.SubprocessError, RuntimeError) as error:
                message = str(error) if isinstance(error, RuntimeError) else 'Could not ' + args.action + ' T3'
                print(json.dumps({'ok': False, 'url': ''', 'error': message}), flush=True)
            return
        now = time.time()
        providers = []
        if installed('claude'):
            providers.append(claude_state(now))
        if installed('codex'):
            providers.append(codex_state(now))
        print(json.dumps({'providers': providers, 't3': t3_state(args.systemctl)}), flush=True)


    if __name__ == '__main__':
        main()
  '';

  aiServiceQml = pkgs.writeText "AiService.qml" ''
    import QtQuick
    import Quickshell
    import Quickshell.Io

    Scope {
        id: service
        property bool active: false
        property bool requested: false
        property string pending: ""
        property string error: ""
        property var state: ({providers:[],t3:{state:"stopped",origin:"",version:"",managed:false}})
        readonly property var providers: state.providers
        // Local intent wins while an action runs, so the button reacts immediately.
        readonly property string t3State: pending==="start" ? "starting" : pending==="stop" ? "stopping"
            : pending==="open" && state.t3.state==="running" ? "running" : state.t3.state
        readonly property bool busy: pending!==""
        signal browserRequested(string url)
        function acceptState(line) {
            try {
                const next=JSON.parse(line);
                if(!Array.isArray(next.providers) || !next.t3 || typeof next.t3.state!=="string")return;
                state=next;
            } catch(error) { /* Keep the last complete frame. */ }
        }
        function acceptAction(line) {
            try {
                const next=JSON.parse(line);
                error=next.error || "";
                if(next.ok && typeof next.url==="string" && /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?\//.test(next.url+"/"))
                    browserRequested(next.url);
            } catch(error) {service.error="Could not read the T3 response";}
        }
        function refresh() {if(active && !collector.running)requested=true;}
        function action(kind) {
            if(busy || !["start","stop","open"].includes(kind))return;
            error="";pending=kind;
            actionProcess.command=["${pkgs.python3}/bin/python3",Quickshell.shellPath("AiBackend.py"),
                "--systemctl","${pkgs.systemd}/bin/systemctl","--systemd-run","${pkgs.systemd}/bin/systemd-run",
                "--steam-run","${pkgs.steam-run}/bin/steam-run","--npx","${pkgs.nodejs_24}/bin/npx",
                "--action",kind];
            actionProcess.running=true;
        }
        function start() {action("start");}
        function stop() {action("stop");}
        function openT3() {action("open");}
        onActiveChanged:{if(active){error="";requested=true;}}
        Process {
            id:collector
            running:service.requested
            command:["${pkgs.python3}/bin/python3",Quickshell.shellPath("AiBackend.py"),
                "--systemctl","${pkgs.systemd}/bin/systemctl"]
            stdout:SplitParser {onRead:data=>service.acceptState(data)}
            onExited:service.requested=false
        }
        Process {
            id:actionProcess
            stdout:SplitParser {onRead:data=>service.acceptAction(data)}
            onExited:(code,status)=>{
                if(code!==0 && service.error==="")service.error="Could not run the T3 action";
                service.pending="";service.requested=true;
            }
        }
        // Server state changes quickly; usage limits are cached by the backend.
        Timer {interval:service.busy?1000:4000;repeat:true;running:service.active;onTriggered:service.refresh()}
    }
  '';

  t3SkyButtonQml = pkgs.writeText "T3SkyButton.qml" ''
    import QtQuick
    import QtQuick.Controls
    import Quickshell.Widgets

    // T3 Code Nightly's app icon as a button: an indigo night sky, a few
    // twinkling stars, banks of violet clouds along the bottom and a heavy "T3".
    AbstractButton {
        id: button
        property string caption: ""
        property bool busy: false
        property bool motionEnabled: true
        property bool animated: true
        property real wordmarkSize: 64
        readonly property bool highlighted: hovered || visualFocus
        property real lift: highlighted ? 1 : 0
        Behavior on lift {NumberAnimation {duration:button.motionEnabled?260:0;easing.type:Easing.OutCubic}}
        property real drift: 0
        NumberAnimation on drift {
            from:0;to:Math.PI*2;duration:button.busy?2400:12000;loops:Animation.Infinite
            running:button.animated && button.motionEnabled && button.visible
        }
        padding: 0
        hoverEnabled: true
        Accessible.name: caption || "T3 Code"
        HoverHandler {cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor}

        background: ClippingRectangle {
            id: sky
            radius: Math.min(30, Math.min(width, height) / 4)
            color: "#0a1531"
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop {position:0;color:"#0a1531"}
                    GradientStop {position:0.55;color:"#141640"}
                    GradientStop {position:1;color:"#2a1454"}
                }
            }
            // Fixed star field, scaled with the button. Each star twinkles on its own beat.
            Repeater {
                model: [[0.18,0.14,2.2,0],[0.34,0.08,1.4,700],[0.62,0.12,1.6,1500],[0.86,0.2,2.4,300],
                    [0.08,0.34,1.3,1100],[0.74,0.3,1.2,1900],[0.48,0.24,1.1,500],[0.93,0.42,1.5,1300],
                    [0.27,0.46,1.0,2300],[0.56,0.4,1.3,900]]
                delegate: Rectangle {
                    id: star
                    required property var modelData
                    x: sky.width*modelData[0]-width/2;y: sky.height*modelData[1]*(1-0.15*button.lift)-height/2
                    width: modelData[2]*(1+0.35*button.lift);height: width;radius: width/2
                    color: "white"
                    property real glow: 1
                    opacity: (0.45+0.55*glow)*(0.75+0.25*button.lift)
                    SequentialAnimation on glow {
                        running: button.animated && button.motionEnabled && button.visible
                        loops: Animation.Infinite
                        PauseAnimation {duration: star.modelData[3]}
                        NumberAnimation {to:0.15;duration:button.busy?380:1400;easing.type:Easing.InOutSine}
                        NumberAnimation {to:1;duration:button.busy?380:1400;easing.type:Easing.InOutSine}
                    }
                }
            }
            // Three cloud banks, back to front. Each bank is one silhouette: a row
            // of overlapping billows merged with a body below, shaded top to bottom
            // and casting a soft shadow onto the bank behind it.
            Canvas {
                id: clouds
                anchors.fill: parent
                property real rise: sky.height*0.04*button.lift
                readonly property var banks: [
                    // [baseline, billow size, sway, top colour, bottom colour, seed, right-heavy]
                    [0.70,0.26,0.030,"#6a4cb6","#3a2a7c",3,1],
                    [0.80,0.22,0.022,"#5d5fc2","#33358a",7,0],
                    [0.92,0.20,0.026,"#7787d2","#4752a6",11,0]
                ]
                function noise(i, seed) {
                    const v = Math.sin(i*12.9898 + seed*78.233)*43758.5453;
                    return v - Math.floor(v);
                }
                onPaint: {
                    const ctx = getContext("2d");ctx.reset();
                    const w = width, h = height, unit = Math.min(w, h*0.85);
                    for (let b = 0; b < banks.length; ++b) {
                        const bank = banks[b];
                        const size = unit*bank[1], step = size*1.15;
                        const sway = w*bank[2]*Math.sin(button.drift + b*2.1);
                        const base = h*bank[0] - rise*(1 - b*0.3);
                        ctx.save();
                        ctx.shadowColor = "rgba(6,6,30,0.55)";
                        ctx.shadowBlur = size*0.45;
                        ctx.shadowOffsetY = -size*0.08;
                        const fill = ctx.createLinearGradient(0, base - size*1.3, 0, h);
                        fill.addColorStop(0, bank[3]);fill.addColorStop(1, bank[4]);
                        ctx.fillStyle = fill;
                        const billows = [];
                        for (let i = -1; i*step < w + step; ++i) {
                            const t = (i*step)/w;
                            // The back bank piles up to the right like the icon.
                            const swell = bank[6] ? 0.55 + 0.75*Math.max(0, Math.min(1, t)) : 1;
                            billows.push({
                                r: size*(0.75 + 0.5*noise(i, bank[5]))*swell,
                                x: i*step + sway + size*0.35*(noise(i + 31, bank[5]) - 0.5),
                                y: base + size*0.3*noise(i + 57, bank[5])
                            });
                        }
                        // Trace the top of the merged billows as one outline.
                        ctx.beginPath();ctx.moveTo(0, h);
                        for (let x = 0; x <= w + 1; x += 1.5) {
                            let top = base;
                            for (const c of billows) {
                                const dx = x - c.x;
                                if (Math.abs(dx) < c.r) top = Math.min(top, c.y - Math.sqrt(c.r*c.r - dx*dx));
                            }
                            ctx.lineTo(x, top);
                        }
                        ctx.lineTo(w + 1, h);ctx.closePath();
                        ctx.fill();
                        ctx.restore();
                    }
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onRiseChanged: requestPaint()
                Component.onCompleted: requestPaint()
                Connections {target:button;function onDriftChanged(){clouds.requestPaint();}}
            }
            Rectangle {
                anchors.fill: parent
                color: "white";opacity: button.pressed ? 0.12 : 0.05*button.lift
            }
            HoverOutline {
                anchors.fill: parent
                cornerRadius: sky.radius
                hovered: button.highlighted
                active: button.enabled
                motionEnabled: button.motionEnabled
            }
        }

        contentItem: Item {
            Text {
                id: wordmark
                anchors.centerIn: parent
                anchors.verticalCenterOffset: button.caption ? -button.height*0.06 : 0
                text: "T3"
                color: "white"
                font.family: "Noto Sans"
                font.weight: Font.Black
                font.pixelSize: button.wordmarkSize
                scale: 1+0.06*button.lift
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: wordmark.bottom;anchors.topMargin: -button.wordmarkSize*0.06
                visible: button.caption !== ""
                text: button.caption
                color: "white"
                font.family: "0xProto Nerd Font Mono"
                font.pixelSize: 11
                opacity: button.enabled ? 0.9 : 0.5
            }
        }
    }
  '';

  aiDetailsQml = pkgs.writeText "AiDetails.qml" ''
    import QtQuick
    import QtQuick.Controls
    import QtQuick.Shapes

    Item {
        id: details
        required property var ai
        property Item glassSource: null
        property point glassPosition: Qt.point(0,0)
        property bool active: false
        property bool motionEnabled: true
        property real now: Date.now()
        property real phase: 0
        readonly property var providers: ai.providers || []
        readonly property bool hasProviders: providers.length > 0
        readonly property string t3State: ai.t3State
        readonly property bool running: t3State === "running" || t3State === "stopping"
        property real runProgress: running ? 1 : 0
        Behavior on runProgress {NumberAnimation {duration:details.motionEnabled?360:0;easing.type:Easing.OutCubic}}
        width: 600;height: 420

        NumberAnimation on phase {
            from:0;to:Math.PI*2;duration:2600;loops:Animation.Infinite
            running:details.active && details.motionEnabled
        }

        function countdown(resetsAt) {
            if (typeof resetsAt !== "number") return "";
            const minutes = Math.max(0, Math.round((resetsAt - now) / 60000));
            if (minutes < 1) return "now";
            const days = Math.floor(minutes / 1440), hours = Math.floor(minutes / 60) % 24, rest = minutes % 60;
            return days ? days + "d " + hours + "h" : hours ? hours + "h " + rest + "m" : rest + "m";
        }
        function ago(updatedAt) {
            if (typeof updatedAt !== "number") return "";
            const minutes = Math.max(0, Math.floor((now - updatedAt) / 60000));
            return minutes < 10 ? "" : minutes < 60 ? minutes + "m ago"
                : minutes < 1440 ? Math.floor(minutes / 60) + "h ago" : Math.floor(minutes / 1440) + "d ago";
        }
        function shortLabel(label) {
            return label === "5-hour" ? "5h" : label === "Weekly" ? "week" : label;
        }
        function tint(rgb) {
            const mix = 0.2, base = 21 / 255;
            return Qt.rgba(base*(1-mix)+rgb[0]/255*mix, base*(1-mix)+rgb[1]/255*mix, base*(1-mix)+rgb[2]/255*mix, 0.75);
        }
        readonly property string t3Version: {
            const match = /nightly\.(\d{4})(\d{2})(\d{2})/.exec(ai.state.t3.version || "");
            return match ? "Nightly " + match[1] + "-" + match[2] + "-" + match[3] : ai.state.t3.version || "Nightly";
        }

        Timer {interval:30000;repeat:true;running:details.active;triggeredOnStart:true;onTriggered:details.now=Date.now()}
        QtObject {
            id: glassContext
            property Item source: details.glassSource
            property Item root: details
            property point origin: details.glassPosition
            property real scale: details.scale
            property int revision: 0
            property var layout: [origin.x,origin.y,scale,details.width,details.height,details.runProgress,details.providers.length]
            onLayoutChanged: Qt.callLater(()=>{revision++;})
        }

        // The providers' own marks, as vector paths.
        component BrandLogo: Item {
            id: brand
            property string kind: "claude"
            readonly property bool claude: kind === "claude"
            readonly property rect box: claude ? Qt.rect(0,0,256,257) : Qt.rect(100,100,411,411)
            Shape {
                width: brand.box.width;height: brand.box.height
                preferredRendererType: Shape.CurveRenderer
                transform: [
                    Translate {x:-brand.box.x;y:-brand.box.y},
                    Scale {xScale:brand.width/brand.box.width;yScale:brand.height/brand.box.height}
                ]
                ShapePath {
                    fillColor: brand.claude ? "#d97757" : "white"
                    strokeColor: "transparent"
                    fillRule: brand.claude ? ShapePath.WindingFill : ShapePath.OddEvenFill
                    PathSvg {path: brand.claude ? "m50.228 170.321 50.357-28.257.843-2.463-.843-1.361h-2.462l-8.426-.518-28.775-.778-24.952-1.037-24.175-1.296-6.092-1.297L0 125.796l.583-3.759 5.12-3.434 7.324.648 16.202 1.101 24.304 1.685 17.629 1.037 26.118 2.722h4.148l.583-1.685-1.426-1.037-1.101-1.037-25.147-17.045-27.22-18.017-14.258-10.37-7.713-5.25-3.888-4.925-1.685-10.758 7-7.713 9.397.649 2.398.648 9.527 7.323 20.35 15.75L94.817 91.9l3.889 3.24 1.555-1.102.195-.777-1.75-2.917-14.453-26.118-15.425-26.572-6.87-11.018-1.814-6.61c-.648-2.723-1.102-4.991-1.102-7.778l7.972-10.823L71.42 0 82.05 1.426l4.472 3.888 6.61 15.101 10.694 23.786 16.591 32.34 4.861 9.592 2.592 8.879.973 2.722h1.685v-1.556l1.36-18.211 2.528-22.36 2.463-28.776.843-8.1 4.018-9.722 7.971-5.25 6.222 2.981 5.12 7.324-.713 4.73-3.046 19.768-5.962 30.98-3.889 20.739h2.268l2.593-2.593 10.499-13.934 17.628-22.036 7.778-8.749 9.073-9.657 5.833-4.601h11.018l8.1 12.055-3.628 12.443-11.342 14.388-9.398 12.184-13.48 18.147-8.426 14.518.778 1.166 2.01-.194 30.46-6.481 16.462-2.982 19.637-3.37 8.88 4.148.971 4.213-3.5 8.62-20.998 5.184-24.628 4.926-36.682 8.685-.454.324.519.648 16.526 1.555 7.065.389h17.304l32.21 2.398 8.426 5.574 5.055 6.805-.843 5.184-12.962 6.611-17.498-4.148-40.83-9.721-14-3.5h-1.944v1.167l11.666 11.406 21.387 19.314 26.767 24.887 1.36 6.157-3.434 4.86-3.63-.518-23.526-17.693-9.073-7.972-20.545-17.304h-1.36v1.814l4.73 6.935 25.017 37.59 1.296 11.536-1.814 3.76-6.481 2.268-7.13-1.297-14.647-20.544-15.1-23.138-12.185-20.739-1.49.843-7.194 77.448-3.37 3.953-7.778 2.981-6.48-4.925-3.436-7.972 3.435-15.749 4.148-20.544 3.37-16.333 3.046-20.285 1.815-6.74-.13-.454-1.49.194-15.295 20.999-23.267 31.433-18.406 19.702-4.407 1.75-7.648-3.954.713-7.064 4.277-6.286 25.47-32.405 15.36-20.092 9.917-11.6-.065-1.686h-.583L44.07 198.125l-12.055 1.555-5.185-4.86.648-7.972 2.463-2.593 20.35-13.999-.064.065Z" : "M252.794 108.802C289.191 99.0484 326.265 110.305 351.148 135.135C385.113 126.072 422.85 134.862 449.492 161.505C476.136 188.149 484.925 225.888 475.862 259.85V259.854C500.696 284.735 511.95 321.81 502.198 358.207C492.447 394.602 464.161 421.084 430.215 430.217C421.083 464.162 394.603 492.448 358.206 502.199C321.812 511.951 284.734 500.693 259.852 475.864C225.887 484.927 188.15 476.137 161.507 449.495C134.864 422.851 126.073 385.111 135.136 351.149C110.304 326.266 99.0496 289.192 108.801 252.795C118.552 216.4 146.84 189.918 180.784 180.785C189.917 146.841 216.396 118.553 252.794 108.802ZM374.292 407.145C374.292 411.271 372.092 415.086 368.517 417.148L283.723 466.102C302.487 480.585 327.555 486.459 352.217 479.852C386.997 470.532 410.068 439.312 410.555 405.006V317.717C410.555 315.08 409.125 312.621 406.843 311.303L374.292 292.509V407.145ZM251.868 415.897C248.296 417.959 243.893 417.959 240.317 415.897L155.526 366.942C152.366 390.436 159.811 415.08 177.866 433.136H177.863C203.325 458.594 241.896 462.962 271.85 446.232L347.449 402.586C349.735 401.268 351.148 398.8 351.148 396.163V358.579L251.868 415.897ZM368.602 220.628C366.319 219.309 363.474 219.318 361.191 220.637L328.641 239.431L427.921 296.749C431.496 298.811 433.697 302.627 433.697 306.752V404.661C455.622 395.654 473.244 376.881 479.851 352.218C489.169 317.442 473.668 281.85 444.201 264.274L368.602 220.628ZM177.303 206.34C155.377 215.348 137.756 234.122 131.148 258.783C121.832 293.561 137.331 329.153 166.799 346.727L242.398 390.373C244.68 391.692 247.525 391.684 249.807 390.366L282.357 371.572L183.078 314.253C179.504 312.189 177.303 308.375 177.303 304.251V206.34ZM259.849 279.145V331.858L305.5 358.213L351.15 331.858V279.145L305.5 252.789L259.849 279.145ZM327.276 144.9C308.512 130.418 283.445 124.543 258.782 131.15C224.002 140.471 200.931 171.691 200.445 205.995V293.286C200.445 295.923 201.875 298.381 204.158 299.7L236.707 318.493V203.856C236.707 199.731 238.909 195.916 242.483 193.853L327.276 144.9ZM433.137 177.867C407.675 152.407 369.103 148.038 339.149 164.769L263.55 208.415C261.265 209.734 259.852 212.202 259.852 214.838V252.423L359.132 195.105C362.703 193.041 367.108 193.041 370.682 195.105L455.473 244.06C458.635 220.567 451.189 195.922 433.135 177.867H433.137Z"}
                }
            }
        }

        // One limit window: a frosted tube filled with white liquid for the
        // share that is left, echoing the active-window meters.
        component LimitMeter: Item {
            id: meter
            property var window: ({})
            property string provider: ""
            property int index: 0
            readonly property bool known: typeof window.remaining === "number"
            readonly property real share: known ? Math.max(0, Math.min(100, window.remaining)) : 0
            property real level: share / 100
            Behavior on level {NumberAnimation {duration:details.motionEnabled?280:0;easing.type:Easing.OutCubic}}
            objectName: "aiLimit-" + provider + "-" + index
            Accessible.role: Accessible.ProgressBar
            Accessible.name: provider + " " + (window.label || "") + " remaining"
            Accessible.description: known ? Math.round(share) + "% left" : "Unavailable"
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: details.shortLabel(meter.window.label || "")
                color: "#aaaaaa";font.family: "0xProto Nerd Font Mono";font.pixelSize: 10
            }
            FrostedSurface {
                id: tube
                anchors.horizontalCenter: parent.horizontalCenter
                y: 18;width: Math.min(44, parent.width);height: parent.height - 18 - 46
                radius: 16;glass: glassContext;tint: "#bf222222"
                Canvas {
                    id: liquid
                    anchors.fill: parent
                    onPaint: {
                        const ctx=getContext("2d");ctx.reset();
                        if(!meter.known||meter.level<=0)return;
                        const baseline=height*(1-meter.level);
                        const amplitude=Math.min(5,2+meter.level*3,baseline,height-baseline);
                        ctx.fillStyle=meter.share<15?"#e57373":"white";ctx.beginPath();ctx.moveTo(0,height);
                        for(let x=0;x<=width;x++)ctx.lineTo(x,baseline+Math.sin(x/width*Math.PI*2-details.phase-meter.index)*amplitude);
                        ctx.lineTo(width,height);ctx.closePath();ctx.fill();
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Component.onCompleted: requestPaint()
                    Connections {target:details;function onPhaseChanged(){liquid.requestPaint();}}
                    Connections {target:meter;function onLevelChanged(){liquid.requestPaint();}function onKnownChanged(){liquid.requestPaint();}}
                }
            }
            UsageValue {
                objectName: "aiRemaining-" + meter.provider + "-" + meter.index
                anchors.horizontalCenter: parent.horizontalCenter
                y: tube.y + tube.height + 8
                text: meter.known ? String(Math.round(meter.share)) : "—"
                unit: meter.known ? "%" : ""
                fontSize: 15;slots: 3
                active: details.active;motionEnabled: details.motionEnabled
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: tube.y + tube.height + 30
                text: details.countdown(meter.window.resetsAt)
                color: "#777777";font.family: "0xProto Nerd Font Mono";font.pixelSize: 9
            }
        }

        // Provider cards: only CLIs that are actually installed appear.
        Row {
            objectName: "aiProviders"
            x: 20;y: 20;width: 340;spacing: 12
            visible: details.hasProviders
            Repeater {
                model: details.providers
                delegate: FrostedSurface {
                    id: card
                    required property var modelData
                    readonly property bool claude: modelData.id === "claude"
                    readonly property var accent: claude ? [217,119,87] : [180,180,180]
                    readonly property string note: modelData.error && modelData.windows.length ? modelData.error
                        : [modelData.plan, details.ago(modelData.updatedAt)].filter(Boolean).join(" · ")
                    objectName: "aiProvider-" + modelData.id
                    width: (340 - 12 * (details.providers.length - 1)) / details.providers.length
                    height: 380
                    radius: 22;glass: glassContext
                    tintGradient: Gradient {
                        GradientStop {position:0;color:details.tint(card.accent)}
                        GradientStop {position:0.5;color:"#bf191919"}
                    }
                    BrandLogo {x:16;y:16;width:22;height:22;kind:card.modelData.id}
                    Text {x:46;y:13;text:card.modelData.name;color:"white";font.family:"0xProto Nerd Font Mono";font.pixelSize:13}
                    Text {
                        x: 46;y: 31;width: parent.width - x - 14
                        text: card.note
                        color: card.modelData.error ? "#c4aaaa" : "#888888"
                        font.family: "0xProto Nerd Font Mono";font.pixelSize: 9;elide: Text.ElideRight
                    }
                    Text {
                        anchors.centerIn: parent;width: parent.width - 32
                        visible: card.modelData.windows.length === 0
                        text: card.modelData.error || "No limits yet"
                        color: "#aaaaaa";font.family: "0xProto Nerd Font Mono";font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter;wrapMode: Text.Wrap
                    }
                    Row {
                        id: meters
                        readonly property int count: Math.max(1, card.modelData.windows.length)
                        x: 16;y: 60;width: card.width - 32;height: card.height - y - 14
                        spacing: 10
                        Repeater {
                            model: card.modelData.windows
                            delegate: LimitMeter {
                                required property var modelData
                                required property int index
                                width: (meters.width - meters.spacing * (meters.count - 1)) / meters.count
                                height: meters.height
                                window: modelData;provider: card.modelData.id;index: index
                            }
                        }
                    }
                }
            }
        }

        // T3 Code: one night-sky Start button, or Open + Stop once the server is up.
        FrostedSurface {
            id: t3Card
            objectName: "t3Card"
            x: details.hasProviders ? 372 : 20;y: 20
            width: details.hasProviders ? 208 : 560;height: 380;radius: 24
            glass: glassContext;tint: "#bf222222"
            readonly property bool hasError: details.ai.error !== ""
            T3SkyButton {
                id: skyButton
                objectName: details.running ? "openT3" : "startT3"
                x: 12;y: 12;width: parent.width - 24
                height: parent.height - 24 - 58 * details.runProgress - (t3Card.hasError ? 22 : 0)
                wordmarkSize: Math.min(width, height) * 0.36
                caption: details.t3State === "running" ? "Take me to T3 ↗" : details.t3State === "starting" ? "Starting…"
                    : details.t3State === "stopping" ? "Stopping…" : "Start"
                busy: details.ai.busy
                enabled: !details.ai.busy
                animated: details.active
                motionEnabled: details.motionEnabled
                onClicked: details.running ? details.ai.openT3() : details.ai.start()
            }
            MediaButton {
                objectName: "stopT3"
                x: 12;y: skyButton.y + skyButton.height + 12;width: parent.width - 24;height: 46
                opacity: details.runProgress;visible: opacity > 0
                enabled: details.t3State === "running" && !details.ai.busy
                glass: glassContext;motionEnabled: details.motionEnabled
                label: "Stop T3 server";glyph: "";iconSize: 18;selected: true
                onClicked: details.ai.stop()
            }
            Text {
                x: 16;y: parent.height - height - 14;width: parent.width - 32
                visible: t3Card.hasError
                text: details.ai.error
                color: "#c4aaaa"
                font.family: "0xProto Nerd Font Mono";font.pixelSize: 9
                horizontalAlignment: Text.AlignHCenter;elide: Text.ElideRight
            }
        }
    }
  '';

  shellQml = pkgs.writeText "shell.qml" ''
    import Quickshell
    import Quickshell.Services.SystemTray
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

        NetworkService {
            id: networkService
            active: expandedState.mounted && expandedState.selected === "network"
            onCommandRequested: command => {root.closeMenu();Quickshell.execDetached(command);}
            onCopyRequested: value => Quickshell.execDetached(["${pkgs.wl-clipboard}/bin/wl-copy", "--", value])
        }

        AiService {
            id: aiService
            active: expandedState.mounted && expandedState.selected === "ai"
            onBrowserRequested: url => {root.closeMenu();Quickshell.execDetached(["${chromium}/bin/chromium", url]);}
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
                    if (moduleDeck.displayed === "network") {
                        const details = dummyTiles.itemAt(2).networkDetailsItem;
                        const p = details.mapFromItem(clockWindow.contentItem, x, y);
                        details.dismissAt(p.x, p.y);
                    }
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
                    cutouts: [clockTile, ...Array.from({length:dummyTiles.count}, (_,i)=>dummyTiles.itemAt(i))]
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
                        : dummyTiles.itemAt(dummyTiles.model.findIndex(item=>item.key===moduleDeck.displayed))
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
                        : moduleDeck.displayed ? dummyTiles.model.findIndex(item=>item.key===moduleDeck.displayed)+1 : -1
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
                            glassSource: clockTile.glassSource
                            glassPosition: clockTile.glassPosition
                            active: visible
                            motionEnabled: root.motionEnabled
                        }

                    }

                    Repeater {
                        id: dummyTiles
                        model: [
                            {key: "media", label: "Media", icon: ""},
                            {key: "usage", label: "Usage", icon: ""},
                            {key: "network", label: "Network", icon: "󰛳"},
                            {key: "apps", label: "Apps", icon: ""},
                            {key: "ai", label: "AI", icon: "󰚩"}
                        ]
                        delegate: ModuleTile {
                            id: dummy
                            required property var modelData
                            required property int index
                            objectName: modelData.key + "Tile"
                            readonly property var previousTile: index>0 ? dummyTiles.itemAt(index-1) : null
                            readonly property real baseX: previousTile
                                ? previousTile.baseX + previousTile.compactWidth + 8 : clockTile.compactWidth + 8
                            readonly property real restX: baseX
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
                            readonly property alias networkDetailsItem: networkDetails
                            readonly property bool audioRevealed: modelData.key === "media"
                                && mediaOutline.visible && (hovered || mediaOutline.progress > 0)
                            glassSource: expandedState.mounted ? backdrop.blurredScene : null
                            glassPosition: morphProgress > 0 ? Qt.point(modulePanel.x, modulePanel.y) : Qt.point(modules.x + x, modules.y)
                            glassOpacity: expandedState.progress
                            accessibleLabel: modelData.key === "media" ? audioService.description : "Open " + modelData.label
                            outlineEnabled: modelData.key === "network" || modelData.key === "apps" || modelData.key === "ai"
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
                                text: dummy.modelData.label
                                color: "#ffffff"
                                font.family: "0xProto Nerd Font Mono"
                                font.pixelSize: 12
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

                            NetworkDetails {
                                id: networkDetails
                                objectName: "networkDetails"
                                width: 600; height: 420
                                scale: clockWindow.detailsScale
                                transformOrigin: Item.TopLeft
                                glassSource: dummy.glassSource
                                glassPosition: dummy.glassPosition
                                opacity: moduleDeck.contentProgress
                                visible: dummy.modelData.key === "network" && dummy.morphProgress > 0 && opacity > 0
                                enabled: visible && moduleDeck.interactive
                                active: networkService.active && visible
                                network: networkService
                                usage: usageService
                                motionEnabled: root.motionEnabled
                            }

                            AppsDetails {
                                objectName: "appsDetails"
                                width: 600; height: 420
                                scale: clockWindow.detailsScale
                                transformOrigin: Item.TopLeft
                                glassSource: dummy.glassSource
                                glassPosition: dummy.glassPosition
                                opacity: moduleDeck.contentProgress
                                visible: dummy.modelData.key === "apps" && dummy.morphProgress > 0 && opacity > 0
                                enabled: visible && moduleDeck.interactive
                                active: expandedState.open && visible
                                window: windowService
                                trayItems: dummy.modelData.key === "apps" ? SystemTray.items : []
                                motionEnabled: root.motionEnabled
                            }

                            AiDetails {
                                objectName: "aiDetails"
                                width: 600; height: 420
                                scale: clockWindow.detailsScale
                                transformOrigin: Item.TopLeft
                                glassSource: dummy.glassSource
                                glassPosition: dummy.glassPosition
                                opacity: moduleDeck.contentProgress
                                visible: dummy.modelData.key === "ai" && dummy.morphProgress > 0 && opacity > 0
                                enabled: visible && moduleDeck.interactive
                                active: expandedState.open && visible
                                ai: aiService
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
                                order: actionButton.index + dummyTiles.count + 2
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
  xdg.configFile."quickshell/NetworkBackend.py".source = networkBackendPython;
  xdg.configFile."quickshell/NetworkService.qml".source = networkServiceQml;
  xdg.configFile."quickshell/NetworkDetails.qml".source = networkDetailsQml;
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
  xdg.configFile."quickshell/AppWindowButton.qml".source = appWindowButtonQml;
  xdg.configFile."quickshell/AppTrayButton.qml".source = appTrayButtonQml;
  xdg.configFile."quickshell/AppsDetails.qml".source = appsDetailsQml;
  xdg.configFile."quickshell/AiBackend.py".source = aiBackendPython;
  xdg.configFile."quickshell/AiService.qml".source = aiServiceQml;
  xdg.configFile."quickshell/T3SkyButton.qml".source = t3SkyButtonQml;
  xdg.configFile."quickshell/AiDetails.qml".source = aiDetailsQml;
  xdg.configFile."quickshell/shell.qml".source = shellQml;
  xdg.configFile."quickshell/ClockVisibility.qml".source = visibilityQml;
  xdg.configFile."quickshell/RollingClock.qml".source = rollingClockQml;
  xdg.configFile."quickshell/HoverOutline.qml".source = hoverOutlineQml;
  xdg.configFile."quickshell/WorkspaceBadge.qml".source = workspaceBadgeQml;

  # Compositor fades include the glass blur. Unmapping leaves no hidden surface
  # or residual frosted patch; disabling compositor animations is respected.
  wayland.windowManager.hyprland.settings.bind = [
    { _args = [ "Super_L" (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("${pkgs.quickshell}/bin/qs ipc call shell toggle")'') ]; }
    { _args = [ "Super_R" (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("${pkgs.quickshell}/bin/qs ipc call shell toggle")'') ]; }
  ];

  wayland.windowManager.hyprland.settings.layer_rule = {
    name = "quickshell-clock-fade";
    match.namespace = "^(quickshell-clock)$";
    animation = "fade";
  };

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
