// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "sunny0826.quick-fcitx"
  ipcTarget: "sunny0826.quick-fcitx"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string controlPath: ""
  property var status: ({
    ready: false,
    mode: "unknown",
    state: 0,
    inputMethod: "",
    fcitxRunning: false,
    message: ""
  })

  property var profile: ({ items: [], defaultIM: "", defaultLayout: "", cnIM: "", enIM: "", group: "" })
  property var available: []
  property var installedPkgs: ({})
  property bool keybindOn: false
  property bool actionBusy: false
  property bool keybindBusy: false
  property bool showAddList: false
  property string errorText: ""
  property string noticeText: ""
  property var pendingArgs: []
  property string pendingNotice: ""

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property string keybindTool: root.localPath(Qt.resolvedUrl("scripts/install-keybind"))

  readonly property var enginePkgs: [
    { pkg: "fcitx5-chinese-addons", label: "拼音 / 五笔等中文扩展" },
    { pkg: "fcitx5-rime", label: "Rime 输入法引擎" },
    { pkg: "fcitx5-hangul", label: "韩语 Hangul" },
    { pkg: "fcitx5-anthy", label: "日语 Anthy" }
  ]
  readonly property var enginePkgNames: enginePkgs.map(function(p) { return p.pkg })
  readonly property var addCandidates: available.filter(function(e) { return !e.installed })

  readonly property string modeLabel: !status.fcitxRunning ? "--"
    : status.mode === "cn" ? "中" : status.mode === "en" ? "en" : "--"
  readonly property bool isCn: status.ready === true && status.mode === "cn"
  readonly property bool canAct: !actionBusy && status.fcitxRunning && controlPath !== ""

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function applyStatus(value) {
    if (value && typeof value === "object") root.status = value
  }

  function itemLabel(name) {
    if (name === profile.cnIM) return name + " · 中文"
    if (name === profile.enIM) return name + " · 英文"
    if (name === profile.defaultIM) return name + " · 默认"
    return name
  }

  function open() {
    root.errorText = ""
    root.noticeText = ""
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function refreshAll() {
    profileProc.running = true
    availProc.running = true
    pkgProc.running = true
    keyProc.running = true
    if (root.hostWidget && root.hostWidget.broadcast)
      root.hostWidget.broadcast("refreshStatus")
  }

  onOpenedChanged: {
    if (opened) root.refreshAll()
  }

  // ---------------------------------------------------------------- actions

  function beginAction(args, notice) {
    if (root.actionBusy || root.controlPath === "") return
    root.actionBusy = true
    root.errorText = ""
    root.noticeText = ""
    root.pendingArgs = args
    root.pendingNotice = notice
    actionProc.running = false
    actionProc.command = [root.controlPath].concat(args)
    actionProc.running = true
  }

  // Switching 中/英 needs the previously focused application to own the input
  // context again, so the panel releases keyboard focus first, then acts.
  function queueModeAction(mode) {
    if (root.actionBusy || root.controlPath === "") return
    root.errorText = ""
    root.noticeText = ""
    root.close()
    root.pendingArgs = ["set-" + mode]
    root.pendingNotice = mode === "cn" ? "已切换到中文" : "已切换到英文"
    modeDelay.restart()
  }

  function installEngine(pkg) {
    if (root.actionBusy) return
    root.errorText = ""
    root.noticeText = "已在终端运行：omarchy pkg add " + pkg + "（完成后重新打开面板查看）"
    // pkg comes only from the readonly enginePkgs whitelist above.
    Quickshell.execDetached([
      "omarchy-launch-terminal", "bash", "-c",
      "omarchy pkg add '" + pkg + "'; rc=$?; echo; " +
      "if [ $rc -ne 0 ]; then echo '安装失败 / Install failed'; fi; " +
      "echo '按回车关闭 / Press Enter to close'; read -r _"
    ])
  }

  function setKeybind(on) {
    if (root.keybindBusy || root.actionBusy || root.keybindTool === "") return
    root.keybindBusy = true
    root.errorText = ""
    root.noticeText = ""
    keyActProc.running = false
    keyActProc.command = [root.keybindTool, on ? "--enable" : "--remove"]
    keyActProc.running = true
  }

  Timer {
    id: modeDelay
    interval: 160
    onTriggered: {
      root.actionBusy = true
      actionProc.running = false
      actionProc.command = [root.controlPath].concat(root.pendingArgs)
      actionProc.running = true
    }
  }

  Timer {
    id: refreshAfterAction
    interval: 250
    onTriggered: root.refreshAll()
  }

  Process {
    id: actionProc

    stderr: StdioCollector {
      id: actionError
      waitForEnd: true
    }

    onExited: function(exitCode) {
      root.actionBusy = false
      if (exitCode !== 0) {
        root.errorText = String(actionError.text || "操作失败").trim().split("\n").slice(-1)[0]
      } else {
        root.noticeText = root.pendingNotice
      }
      root.pendingNotice = ""
      refreshAfterAction.restart()
    }
  }

  Process {
    id: keyActProc

    stderr: StdioCollector {
      id: keyError
      waitForEnd: true
    }

    onExited: function(exitCode) {
      root.keybindBusy = false
      if (exitCode !== 0) {
        root.errorText = String(keyError.text || "键绑定操作失败").trim().split("\n").slice(-1)[0]
      } else {
        root.noticeText = root.keybindOn
          ? "已移除：轻点左 Shift 切换"
          : "已启用：轻点左 Shift 切换中英文"
      }
      keyProc.running = true
      refreshAfterAction.restart()
    }
  }

  // ------------------------------------------------------------------- data

  Process {
    id: profileProc
    command: [root.controlPath, "profile-list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var value = JSON.parse(text || "{}")
          if (value && value.items) root.profile = value
        } catch (error) {}
      }
    }
  }

  Process {
    id: availProc
    command: [root.controlPath, "available"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var value = JSON.parse(text || "{}")
          if (value && value.available) root.available = value.available
        } catch (error) {}
      }
    }
  }

  Process {
    id: pkgProc
    command: ["pacman", "-Q"].concat(root.enginePkgNames)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var found = {}
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].split(" ")[0]
          if (name) found[name] = true
        }
        root.installedPkgs = found
      }
    }
  }

  Process {
    id: keyProc
    command: [root.keybindTool, "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.keybindOn = String(text || "").indexOf("enabled") === 0
    }
  }

  // ------------------------------------------------------------------ panel

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.actionBusy || root.keybindBusy || pathField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "c" || text === "C") root.queueModeAction("cn")
        else if (text === "e" || text === "E") root.queueModeAction("en")
        else if (text === "r" || text === "R") root.beginAction(["restart"], "已重启 Fcitx5")
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(6)

        // ------------------------------------------------------- status row
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Text {
            id: modeText
            text: root.modeLabel
            color: root.isCn ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.status.message || ""
            elide: Text.ElideRight
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            verticalAlignment: Text.AlignVCenter
          }

          PanelActionButton {
            id: restartBtn
            Layout.alignment: Qt.AlignVCenter
            iconText: "↻"
            tooltipText: "重启 Fcitx5"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: root.canAct
            onClicked: root.beginAction(["restart"], "已重启 Fcitx5")
          }
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        // -------------------------------------------------- input method list
        PanelSectionHeader {
          width: parent.width
          text: "输入法 · " + (root.profile.group || "-")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          model: root.profile.items

          RowLayout {
            width: content.width
            height: Style.space(30)
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              text: root.itemLabel(modelData)
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              verticalAlignment: Text.AlignVCenter
            }

            PanelActionButton {
              id: delBtn
              Layout.alignment: Qt.AlignVCenter
              iconText: "✕"
              tooltipText: "从配置组移除"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.profile.items.length > 1 && !root.actionBusy
              onClicked: root.beginAction(["profile-remove", modelData], "已移除 " + modelData)
            }
          }
        }

        Button {
          width: parent.width
          text: root.showAddList ? "− 收起添加列表" : "+ 添加输入法"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.showAddList = !root.showAddList
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.showAddList

          Repeater {
            model: root.addCandidates

              RowLayout {
                width: content.width
                height: Style.space(30)
                spacing: Style.space(8)

                Text {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  text: modelData.name + "（" + modelData.code + "）"
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                verticalAlignment: Text.AlignVCenter
              }

              PanelActionButton {
                id: addBtn
                Layout.alignment: Qt.AlignVCenter
                iconText: "+"
                tooltipText: "加入当前配置组"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: root.canAct
                onClicked: root.beginAction(["profile-add", modelData.code], "已添加 " + modelData.code)
              }
            }
          }

          Text {
            width: parent.width
            visible: root.addCandidates.length === 0
            text: "没有更多可添加的输入法；先在下方「安装引擎」安装。"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        // ---------------------------------------------------- engine install
        PanelSectionHeader {
          width: parent.width
          text: "安装引擎"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          model: root.enginePkgs

          RowLayout {
            width: content.width
            height: Style.space(30)
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              text: modelData.label + "（" + modelData.pkg + "）"
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              verticalAlignment: Text.AlignVCenter
            }

            Text {
              id: stateLabel
              Layout.alignment: Qt.AlignVCenter
              visible: root.installedPkgs[modelData.pkg] === true
              text: "已安装"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              verticalAlignment: Text.AlignVCenter
            }

            Button {
              id: installBtn
              Layout.alignment: Qt.AlignVCenter
              visible: !root.installedPkgs[modelData.pkg]
              text: "安装"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.installEngine(modelData.pkg)
            }
          }
        }

        Text {
          width: parent.width
          text: "安装会在可见终端中执行 omarchy pkg add，需要输入你的密码。"
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        // ------------------------------------------------------- rime import
        PanelSectionHeader {
          width: parent.width
          text: "导入 Rime 方案"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          TextField {
            id: pathField
            Layout.fillWidth: true
            foreground: root.foreground
            accent: root.accent
            font.pixelSize: Style.font.caption
            placeholderText: "路径，如 ~/rime/foo.custom.yaml"
          }

          Button {
            id: importBtn
            Layout.alignment: Qt.AlignVCenter
            text: "导入"
            enabled: !root.actionBusy && pathField.text.length > 0 && root.canAct
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.beginAction(["import-rime", pathField.text.trim()], "已导入 Rime 方案")
          }
        }

        Text {
          width: parent.width
          text: "支持 .yaml / .yml / .bin，复制到 ~/.local/share/fcitx5/rime/ 并重启 Fcitx5 生效；需先安装 fcitx5-rime。"
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        // ---------------------------------------------------- left-shift key
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: "轻点左 Shift 切换中英文"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            verticalAlignment: Text.AlignVCenter
          }

          ToggleSwitch {
            id: keybindToggle
            Layout.alignment: Qt.AlignVCenter
            checked: root.keybindOn
            busy: root.keybindBusy
            interactive: !root.keybindBusy && !root.actionBusy
            foreground: root.foreground
            accent: root.accent
            onToggled: root.setKeybind(checked)
          }
        }

        Text {
          width: parent.width
          text: "单独按一下左 Shift 切换中/英，Shift+字母 打大写不受影响。启用时会向 ~/.config/hypr/bindings.lua 写入一个可随时移除的托管代码块。"
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ------------------------------------------------------- feedback row
        Text {
          width: parent.width
          visible: root.errorText !== ""
          text: root.errorText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.noticeText !== ""
          text: root.noticeText
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
