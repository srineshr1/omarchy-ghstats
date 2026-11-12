import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.ricky.ghstats"
  ipcTarget: "io.github.ricky.ghstats"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  property bool unreadOnly: true
  property int cursorIndex: 0
  property bool cursorActive: false
  property bool openedFromHotkey: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color secondaryForeground: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool excludeCi: root.setting("excludeCi", true) === true

  readonly property var visibleNotifications: {
    var list = service ? service.notifications : []
    return Model.filterNotifications(list, root.unreadOnly, root.excludeCi)
  }
  readonly property int visibleUnread: service ? service.visibleUnread : 0
  readonly property bool authenticated: service ? service.authenticated : false
  readonly property bool loading: service ? service.refreshing && !(service.ok) : false
  readonly property int heatmapWidth: {
    var weeks = service && service.weeks ? service.weeks.length : 53
    var cell = Style.space(9)
    var gap = Style.space(2)
    return Style.space(16) + weeks * cell + Math.max(0, weeks - 1) * gap
  }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    if (service) service.refresh()
    root.controller.show()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    if (service) service.refresh()
    root.controller.show()
    Qt.callLater(function () {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    // Hide first so nothing below can leave the full-screen overlay stuck open.
    root.controller.hide()
    setCenterHoverRevealSuppressed(false)
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Third-party widgets get a PluginBarApi whose centerHoverRevealSuppressed
  // is read-only; assigning it throws, so go through the setter when present.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    if (service) service.refresh()
  }

  function notificationAt(index) {
    var list = root.visibleNotifications
    if (index < 0 || index >= list.length) return null
    return list[index]
  }

  function moveCursor(dy) {
    var count = root.visibleNotifications.length
    if (count === 0) {
      cursorActive = false
      return
    }
    if (!cursorActive) {
      cursorActive = true
      cursorIndex = dy > 0 ? 0 : count - 1
    } else {
      cursorIndex = Math.max(0, Math.min(count - 1, cursorIndex + dy))
    }
    Qt.callLater(scrollCursorIntoView)
  }

  function activateCursor() {
    var row = notificationAt(cursorIndex)
    if (row) openNotification(row)
  }

  function openNotification(row) {
    if (!row || !service) return
    service.openUrl(Model.notificationUrl(row))
    if (row.unread) service.markRead(row.id)
  }

  function dismissNotification(row) {
    if (!row || !service) return
    service.markDone(row.id)
  }

  function dismissCursor() {
    var row = notificationAt(cursorIndex)
    if (row) dismissNotification(row)
  }

  function scrollCursorIntoView() {
    if (!notifRepeater || cursorIndex < 0 || cursorIndex >= notifRepeater.count) return
    var item = notifRepeater.itemAt(cursorIndex)
    if (!item || !panelFlick) return
    var point = item.mapToItem(panelFlick.contentItem, 0, 0)
    var top = point.y
    var bottom = top + item.height
    var margin = Style.space(8)
    if (top < panelFlick.contentY + margin)
      panelFlick.contentY = Math.max(0, top - margin)
    else if (bottom > panelFlick.contentY + panelFlick.height - margin)
      panelFlick.contentY = Math.max(0, bottom - panelFlick.height + margin)
  }

  onVisibleNotificationsChanged: {
    if (cursorIndex >= visibleNotifications.length)
      cursorIndex = Math.max(0, visibleNotifications.length - 1)
    if (visibleNotifications.length === 0) cursorActive = false
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(520), root.heatmapWidth + Style.space(40)))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onMoveRequested: function (dx, dy) { root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.dismissCursor()
      onTextKey: function (text) {
        if (text === "r" || text === "R") root.refresh()
        else if (text === "u" || text === "U") root.unreadOnly = true
        else if (text === "a" || text === "A") root.unreadOnly = false
        else if (text === "e" || text === "E") root.dismissCursor()
        else if (text === "o" || text === "O") {
          if (root.service) root.service.openUrl("https://github.com/notifications")
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: root.authenticated && root.service && root.service.login
              ? "@" + root.service.login
              : "GitHub"
            meta: {
              if (root.loading) return "Loading…"
              if (!root.authenticated) return "Not signed in"
              var total = root.service ? root.service.totalContributions : 0
              var streak = root.service ? root.service.streak : 0
              var bits = [total + " this year"]
              if (streak > 0) bits.push(streak + " day streak")
              return bits.join(" \u00b7 ")
            }
            detail: root.visibleUnread > 0 ? root.visibleUnread + " unread" : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "\uf09b"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "\uf021"
                tooltipText: "Refresh"
                enabled: root.service && !root.service.refreshing
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.refresh()
              }
            }
          }

          Text {
            visible: {
              if (!root.authenticated) return true
              var err = root.service ? root.service.lastError : ""
              return err && err.length > 0
            }
            width: parent.width
            text: {
              if (!root.authenticated) {
                var hint = root.service ? root.service.hint : ""
                var err = root.service ? root.service.lastError : ""
                return (err || "Sign in with the GitHub CLI") + (hint ? "\n" + hint : "\nRun: gh auth login")
              }
              return root.service.lastError
            }
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          ContributionGrid {
            id: heatmap
            visible: root.authenticated && root.service && root.service.weeks.length > 0
            width: parent.width
            mode: "calendar"
            weeks: root.service ? Model.padWeeks(root.service.weeks) : []
            todayKey: Qt.formatDate(new Date(), "yyyy-MM-dd")
            accent: Color.accent
            empty: root.foreground
            foreground: root.foreground
            fontFamily: root.fontFamily
            cellSize: Style.space(9)
            cellGap: Style.space(2)
          }

          PanelSeparator { foreground: root.foreground }

          Item {
            width: parent.width
            implicitHeight: Math.max(sectionHeader.implicitHeight, filterRow.implicitHeight)

            PanelSectionHeader {
              id: sectionHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "NOTIFICATIONS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              id: filterRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Text {
                text: "Unread"
                color: root.unreadOnly ? root.foreground : root.secondaryForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: root.unreadOnly
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.unreadOnly = true
                }
              }
              Text {
                text: "All"
                color: !root.unreadOnly ? root.foreground : root.secondaryForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: !root.unreadOnly
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.unreadOnly = false
                }
              }
            }
          }

          Text {
            visible: root.visibleNotifications.length === 0
            width: parent.width
            text: {
              if (!root.authenticated) return "Inbox needs a GitHub login."
              if (root.unreadOnly) return root.excludeCi ? "You're all caught up." : "No unread notifications."
              return "No notifications."
            }
            color: root.secondaryForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Column {
            id: notifColumn
            visible: root.visibleNotifications.length > 0
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              id: notifRepeater
              model: root.visibleNotifications

              CursorSurface {
                required property var modelData
                required property int index
                width: notifColumn.width
                implicitHeight: row.implicitHeight + Style.space(10)
                foreground: root.foreground
                accent: Color.accent
                hasCursor: root.cursorActive && root.cursorIndex === index
                current: modelData.unread === true

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton
                  onEntered: {
                    root.cursorActive = true
                    root.cursorIndex = index
                  }
                  onClicked: root.openNotification(modelData)
                }

                Row {
                  id: row
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(10)
                  z: 1

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.typeGlyph(modelData.type)
                    color: modelData.unread ? root.foreground : root.secondaryForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                    width: Style.space(18)
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Column {
                    width: parent.width - Style.space(18) - Style.space(28) - Style.space(20)
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      text: Model.truncate(modelData.title, 78)
                      // Untrusted GitHub titles; AutoText would load remote resources.
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: {
                        var bits = []
                        if (modelData.repo) bits.push(modelData.repo)
                        var reason = Model.reasonLabel(modelData.reason)
                        if (reason) bits.push(reason)
                        var when = Model.relativeTime(modelData.updatedAt, Date.now())
                        if (when) bits.push(when)
                        return bits.join(" \u00b7 ")
                      }
                      textFormat: Text.PlainText
                      color: root.secondaryForeground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  PanelActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "\uf00c"
                    tooltipText: "Done"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.dismissNotification(modelData)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
