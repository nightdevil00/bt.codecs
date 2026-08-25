import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "local.btcodec"
  ipcTarget: "local.btcodec"

  property var cards: []
  property var displayRows: []

  readonly property var activeCard: Model.activeCard(cards)
  readonly property string barText: {
    var c = root.activeCard
    if (!c) return "󰂲"
    var codec = Model.codecShort(c)
    return codec !== "" ? "󰋋 " + codec : "󰋋"
  }
  readonly property string heroSubtitle: {
    var c = root.activeCard
    if (!c) return "No Bluetooth audio device"
    var codec = Model.codecShort(c)
    return (c.description || c.deviceName || c.name) + (codec !== "" ? " \u00b7 " + codec : "")
  }

  readonly property color hoverFill: bar
    ? Style.hoverFillFor(bar.foreground, Color.accent)
    : "transparent"
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Color.accent)
    : "transparent"

  // Single flat list: a header row per connected Bluetooth audio card,
  // then one row per available profile. Enter/Space (or click) sets it.
  property string focusSection: "rows"
  property int selectedIndex: 0
  property bool cursorActive: false

  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  function onCardsRaw(raw) {
    cards = Model.parseCards(raw)
    if (opened) {
      displayRows = Model.buildRows(cards)
      clampCursor()
    }
  }

  function setProfile(row) {
    if (!row || row.kind !== "profile") return
    Quickshell.execDetached([
      "pactl", "set-card-profile",
      String(row.card.name),
      String(row.profile.name)
    ])
    refreshTimer.restart()
  }

  function clampCursor() {
    if (displayRows.length === 0) { selectedIndex = 0; return }
    if (selectedIndex > displayRows.length - 1) selectedIndex = displayRows.length - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  function moveCursor(delta) {
    if (displayRows.length === 0) return
    selectedIndex = Math.max(0, Math.min(displayRows.length - 1, selectedIndex + delta))
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      displayRows = Model.buildRows(cards)
      clampCursor()
      cursorActive = false
    } else {
      displayRows = []
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: listProc
    command: ["pactl", "list", "cards"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onCardsRaw(text)
    }
  }

  // Keeps the bar label's codec current while the panel is closed.
  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Faster refresh while the panel is open so changes settle quickly.
  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // Right after a profile change, re-read so the new active row lights up.
  Timer {
    id: refreshTimer
    interval: 700
    repeat: false
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    tooltipText: "Bluetooth audio codec"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.setProfile(root.displayRows[root.selectedIndex])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(14)

        // ---------- Hero: headphones icon · device + codec ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.activeCard ? "󰋋" : "󰂲"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            opacity: root.activeCard ? 1.0 : 0.5
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Bluetooth codec"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.heroSubtitle.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Text {
          visible: root.displayRows.length === 0
          text: root.activeCard
            ? "No selectable profiles"
            : "No Bluetooth audio devices connected"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          width: parent.width
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.displayRows

            delegate: Item {
              required property var modelData
              required property int index

              readonly property var entry: modelData
              width: column.width
              height: entry && entry.kind === "header"
                ? headerText.implicitHeight + Style.space(4)
                : profileRow.implicitHeight

              Text {
                id: headerText
                visible: entry && entry.kind === "header"
                text: entry && entry.kind === "header" ? String(entry.text || "").toUpperCase() : ""
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }

              ProfileRow {
                id: profileRow
                visible: entry && entry.kind === "profile"
                width: parent.width
                row: entry
                rowIndex: index
              }
            }
          }
        }
      }
    }
  }

  component ProfileRow: CursorSurface {
    id: profileRow
    required property var row
    required property int rowIndex

    readonly property bool isActive: !!(row.profile && row.profile.active)
    hasCursor: root.cursorActive && root.selectedIndex === rowIndex
    current: isActive
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: rowInner.implicitHeight + Style.spacing.xl

    Item {
      id: rowInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      implicitHeight: Math.max(iconText.implicitHeight, labelText.implicitHeight, descText.implicitHeight)

      Text {
        id: iconText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: profileRow.isActive ? "󰄳" : "󰇄"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(20)
        horizontalAlignment: Text.AlignHCenter
      }

      Item {
        id: labelClip
        anchors.left: iconText.right
        anchors.leftMargin: Style.space(8)
        anchors.right: descText.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        height: labelText.implicitHeight
        clip: true

        Text {
          id: labelText
          anchors.verticalCenter: parent.verticalCenter
          text: row.profile ? row.profile.label : ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: profileRow.isActive

          SequentialAnimation on x {
            id: marqueeAnim
            running: root.opened && labelText.text !== ""
              && labelText.implicitWidth > labelClip.width
            loops: Animation.Infinite

            PauseAnimation { duration: 600 }
            PropertyAnimation {
              to: Math.min(0, labelClip.width - labelText.implicitWidth)
              duration: Math.max(800, Math.abs(labelText.implicitWidth - labelClip.width) * 2)
              easing.type: Easing.Linear
            }
            PauseAnimation { duration: 600 }
          }

          Component.onCompleted: {
            if (root.opened && marqueeAnim.running) marqueeAnim.start()
            else x = 0
          }
        }
      }

      Text {
        id: descText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: row.profile ? row.profile.description : ""
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.selectedIndex = profileRow.rowIndex
      }
      onClicked: root.setProfile(profileRow.row)
    }
  }
}
