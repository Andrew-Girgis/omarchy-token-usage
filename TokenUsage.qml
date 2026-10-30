import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "girgie.token-usage"
  ipcTarget: moduleName
  manageIpc: false
  property string fixedEdge: "end"
  readonly property bool vertical: bar ? bar.vertical : false
  property string period: "1d"
  property var snapshots: ({})
  property var today: null
  property string fetchingPeriod: ""
  property int viewIndex: 0
  property bool projectTime: false
  property int activityIndex: 0
  property int rankLimit: 12
  readonly property var snapshot: snapshots[period] || null
  readonly property var usageData: snapshot ? snapshot.data : ({})
  readonly property var overview: usageData.overview || null
  readonly property var tokens: usageData.tokens ? usageData.tokens.totals : overview ? overview.tokens : null
  readonly property var time: overview ? overview.time : null
  readonly property bool autoRefresh: setting("autoRefresh", true) === true
  readonly property bool busy: detailProc.running
  readonly property var periods: ["1d", "7d", "30d", "all"]
  readonly property var tabs: [catalog.t("tab.overview"), catalog.t("tab.models"), catalog.t("tab.projects"), catalog.t("tab.activity"), catalog.t("tab.sources")]

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }

  function compact(n) { return Model.compact(n, Commons.I18n.formatNumber) }
  function count(n) { return n === null || n === undefined ? "—" : Commons.I18n.formatNumber(n, 0) }
  function duration(n) {
    if (n === null || n === undefined) return "—"
    var p = Model.timeParts(n)
    return catalog.t("duration").arg(count(p[0])).arg(count(p[1]))
  }
  function dateLabel(value) { return new Date(value).toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), "d MMM yyyy") }
  function periodLabel(value) { return value === "all" ? catalog.t("range.all") : value.toUpperCase() }
  function choosePeriod(value) {
    if (periods.indexOf(value) < 0) return
    period = value
    loadDetails(false)
  }
  function loadDetails(force) {
    if (detailProc.running) { pendingRefresh = true; return }
    fetchingPeriod = period
    detailProc.command = ["/usr/bin/python3", Qt.resolvedUrl("usage.py").toString().replace(/^file:\/\//, ""), "--range", period].concat(force ? ["--refresh"] : [])
    detailProc.running = true
    detailTimeout.restart()
  }
  property bool pendingRefresh: false
  function refresh() {
    loadToday(true)
    if (opened) loadDetails(true)
  }
  function loadToday(force) {
    if (summaryProc.running) return
    summaryProc.command = ["/usr/bin/python3", Qt.resolvedUrl("usage.py").toString().replace(/^file:\/\//, ""), "--range", "1d", "--summary"].concat(force ? ["--refresh"] : [])
    summaryProc.running = true
    summaryTimeout.restart()
  }
  function receive(raw, summary) {
    try {
      if (raw.length > 2097152) return
      var result = JSON.parse(raw)
      if (!result || periods.indexOf(result.period) < 0 || !result.data) return
      if (summary) today = result
      else {
        var copy = Object.assign({}, snapshots)
        copy[result.period] = result
        snapshots = copy
        if (result.period === "1d") today = result
      }
    } catch (e) { console.warn("Token Usage: invalid helper response") }
  }
  function helperFailed(summary) {
    var old = summary ? today : snapshots[fetchingPeriod]
    var failed = {period: summary ? "1d" : fetchingPeriod,
      status: old && old.data.overview ? "stale" : "error",
      fetched_at: old ? old.fetched_at : 0, data: old ? old.data : ({}), errors: ["helper_failed"]}
    if (summary) today = failed
    else {
      var copy = Object.assign({}, snapshots)
      copy[fetchingPeriod] = failed
      snapshots = copy
    }
  }
  function toggleAuto() {
    var entry = Object.assign({}, settings, {id: moduleName, autoRefresh: !autoRefresh})
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }
  onOpenedChanged: if (opened) loadDetails(false)
  onPeriodChanged: rankLimit = 12
  onViewIndexChanged: rankLimit = 12
  Component.onCompleted: loadToday(false)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  ShellIpc {
    target: root.moduleName
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function selectRange(value: string): void { root.choosePeriod(value) }
    function selectTab(value: string): void {
      var index = ["overview", "models", "projects", "activity", "sources"].indexOf(value)
      if (index >= 0) root.viewIndex = index
    }
    function status(): string {
      return JSON.stringify({period: root.period, tab: root.viewIndex, busy: root.busy,
        status: root.snapshot ? root.snapshot.status : "loading", autoRefresh: root.autoRefresh,
        total: root.tokens ? root.tokens.total : null})
    }
  }
  Process {
    id: summaryProc
    stdout: StdioCollector { onStreamFinished: root.receive(text, true) }
    onExited: function(exitCode) { summaryTimeout.stop(); if (exitCode !== 0) root.helperFailed(true) }
  }
  Process {
    id: detailProc
    stdout: StdioCollector { onStreamFinished: root.receive(text, false) }
    onExited: function(exitCode) {
      detailTimeout.stop()
      if (exitCode !== 0) root.helperFailed(false)
      if (root.pendingRefresh || root.fetchingPeriod !== root.period) {
        root.pendingRefresh = false
        if (root.opened) Qt.callLater(function() { root.loadDetails(false) })
      }
    }
  }
  Timer { id: summaryTimeout; interval: 50000; onTriggered: summaryProc.running = false }
  Timer { id: detailTimeout; interval: 50000; onTriggered: detailProc.running = false }
  Timer { interval: 300000; repeat: true; running: root.autoRefresh; onTriggered: root.loadToday(false) }
  Timer { interval: 60000; repeat: true; running: root.autoRefresh && root.opened; onTriggered: root.loadDetails(false) }

  WidgetButton {
    id: button
    bar: root.bar
    anchors.fill: parent
    text: {
      var o = root.today && root.today.data ? root.today.data.overview : null
      var n = o ? root.compact(o.tokens.total) : "—"
      return root.vertical ? "󰚩" : catalog.t("bar.label").arg(n) + (root.today && root.today.status === "stale" ? " ·" : "")
    }
    tooltipText: Model.sharedText(catalog.t("bar.tooltip"))
    onPressed: function(b) { if (b === Qt.MiddleButton || b === Qt.RightButton) root.refresh(); else root.toggle() }
  }

  component Heading: UsageText { font.pixelSize: Style.font.title; font.bold: true }
  component Note: UsageText { width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: Style.font.bodySmall; opacity: 0.65 }
  component Rule: Rectangle { width: parent.width; height: 1; color: Qt.alpha(Commons.Color.popups.text, 0.1) }
  component Stat: Column {
    property string title: ""
    property string value: ""
    spacing: Style.space(4)
    UsageText { text: parent.value; font.pixelSize: Style.font.title; font.bold: true }
    UsageText { text: parent.title; font.pixelSize: Style.font.bodySmall; opacity: 0.6 }
  }

  KeyboardPanel {
    id: panel
    bar: root.bar
    anchorItem: button
    owner: root
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(660))
    contentHeight: panel.cappedContentHeight(Style.space(760))

    content: PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) {
        if (dx) root.choosePeriod(root.periods[(root.periods.indexOf(root.period) + dx + 4) % 4])
        if (dy) scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, scroll.contentY + dy * Style.space(65)))
      }
      onTabRequested: function(direction) { root.viewIndex = (root.viewIndex + direction + root.tabs.length) % root.tabs.length }
      onTextKey: function(t) {
        if (t === "r") root.refresh()
        var n = parseInt(t)
        if (n >= 1 && n <= 4) root.choosePeriod(root.periods[n - 1])
      }

      Column {
        id: top
        width: parent.width
        spacing: Style.space(12)
        Row {
          width: parent.width
          spacing: Style.space(6)
          Heading { text: catalog.t("title"); width: parent.width - autoButton.width - refreshButton.width - closeButton.width - Style.space(18); anchors.verticalCenter: parent.verticalCenter }
          Button { id: autoButton; text: root.autoRefresh ? catalog.t("auto.on") : catalog.t("auto.off"); selected: root.autoRefresh; onClicked: root.toggleAuto() }
          Button { id: refreshButton; text: root.busy ? catalog.t("loading.short") : catalog.t("refresh"); enabled: !root.busy; onClicked: root.refresh() }
          Button { id: closeButton; text: "×"; tooltipText: Model.sharedText(catalog.t("close")); onClicked: root.close() }
        }
        Row {
          spacing: Style.space(6)
          Repeater {
            model: root.periods
            Button {
              required property string modelData
              text: root.periodLabel(modelData)
              selected: root.period === modelData
              horizontalPadding: Style.space(22)
              onClicked: root.choosePeriod(modelData)
            }
          }
        }
        Row {
          width: parent.width
          spacing: Style.space(3)
          Repeater {
            model: root.tabs
            Button {
              required property string modelData
              required property int index
              text: modelData
              fontSize: Style.font.bodySmall
              selected: root.viewIndex === index
              horizontalPadding: Style.space(9)
              onClicked: root.viewIndex = index
            }
          }
        }
        Rule {}
      }

      Flickable {
        id: scroll
        anchors.top: top.bottom
        anchors.topMargin: Style.space(14)
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(12)
        width: parent.width
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
          id: body
          width: scroll.width - Style.space(8)
          spacing: Style.space(18)
          Note {
            visible: !root.overview
            text: root.busy ? catalog.t("loading") : catalog.t("error")
          }
          Note {
            visible: root.snapshot && root.snapshot.status !== "ok" && root.overview !== null
            color: Commons.Color.urgent; opacity: 1
            text: root.snapshot && root.snapshot.status === "stale" ? catalog.t("stale") : catalog.t("partial")
          }

          Column {
            visible: root.overview !== null && root.viewIndex === 0
            width: parent.width
            spacing: Style.space(18)
            Column {
              width: parent.width; spacing: Style.space(3)
              UsageText { text: root.tokens ? root.compact(root.tokens.total) : "—"; font.pixelSize: Style.font.display * 1.35; font.bold: true; color: Commons.Color.accent }
              UsageText { text: catalog.t("tokens.provisional"); opacity: 0.7 }
              Note { text: catalog.t("tokens.exact").arg(root.tokens ? root.count(root.tokens.total) : "—") }
            }
            Row {
              width: parent.width
              Stat { width: parent.width / 3; title: catalog.t("input"); value: root.tokens ? root.compact(root.tokens.input) : "—" }
              Stat { width: parent.width / 3; title: catalog.t("output"); value: root.tokens ? root.compact(root.tokens.output) : "—" }
              Stat { width: parent.width / 3; title: catalog.t("cache.share"); value: root.tokens && root.tokens.total ? Commons.I18n.formatNumber(root.tokens.cached_input / root.tokens.total * 100, 1) + "%" : "—" }
            }
            Rule {}
            Column {
              width: parent.width; spacing: Style.space(10)
              Heading { text: catalog.t("coding.title") }
              Row {
                width: parent.width
                Stat { width: parent.width / 3; title: catalog.t("coding.ai"); value: root.duration(root.time ? root.time.agent_seconds : null) }
                Stat { width: parent.width / 3; title: catalog.t("coding.you"); value: root.duration(root.time ? root.time.you_seconds : null) }
                Stat { width: parent.width / 3; title: catalog.t("coding.overlap"); value: root.duration(root.time ? root.time.overlap_seconds : null) }
              }
              Row {
                width: parent.width; height: Style.space(10)
                Repeater {
                  model: Model.timeSegments(root.time)
                  Rectangle {
                    required property real modelData
                    required property int index
                    width: root.time && root.time.total_seconds > 0 ? parent.width * modelData / root.time.total_seconds : 0
                    height: parent.height
                    color: index === 0 ? Commons.Color.accent : index === 1 ? Commons.Color.popups.text : Commons.Color.urgent
                  }
                }
              }
              Note {
                text: catalog.t("coding.share")
                  .arg(root.time && root.time.total_seconds > 0 ? Commons.I18n.formatNumber(root.time.agent_seconds / root.time.total_seconds * 100, 1) : "—")
                  .arg(root.time && root.time.total_seconds > 0 ? Commons.I18n.formatNumber(root.time.you_seconds / root.time.total_seconds * 100, 1) : "—")
              }
              Note { text: catalog.t("coding.note") }
              Note { visible: root.time !== null && root.time.you_seconds === 0; text: catalog.t("coding.noManual") }
            }
            Rule {}
            Column {
              width: parent.width; spacing: Style.space(10)
              Heading { text: catalog.t("trend.title") }
              TrendChart { width: parent.width; days: root.usageData.tokens ? root.usageData.tokens.days : []; strings: catalog }
            }
            Column {
              width: parent.width; spacing: Style.space(10)
              Heading { text: catalog.t("mix.title") }
              RankedBars {
                width: parent.width; strings: catalog; emptyText: catalog.t("empty.tokens")
                rows: root.tokens ? [
                  {name: catalog.t("cache.read"), value: root.tokens.cached_input},
                  {name: catalog.t("cache.write"), value: root.tokens.cache_write},
                  {name: catalog.t("input"), value: root.tokens.input},
                  {name: catalog.t("output"), value: root.tokens.output},
                  {name: catalog.t("input.unknown"), value: root.tokens.unknown_input}
                ] : []
              }
            }
            Row {
              width: parent.width
              Stat { width: parent.width / 3; title: catalog.t("sessions"); value: root.usageData.activity ? root.count(root.usageData.activity.sessions) : "—" }
              Stat { width: parent.width / 3; title: catalog.t("activeDays"); value: root.usageData.activity ? root.count(root.usageData.activity.active_days) : "—" }
              Stat { width: parent.width / 3; title: catalog.t("medianSession"); value: root.usageData.activity ? root.duration(root.usageData.activity.median_seconds) : "—" }
            }
            Column {
              width: parent.width; spacing: Style.space(5)
              UsageText { text: root.overview && root.overview.cost ? catalog.t("cost.value").arg(root.overview.cost.currency).arg(Commons.I18n.formatNumber(root.overview.cost.value, 2)) : catalog.t("cost.unavailable"); font.bold: true }
              Note { text: catalog.t("cost.note") }
              Note { visible: root.overview !== null && root.overview.cost !== null; text: catalog.t("cost.unpriced").arg(root.overview && root.overview.cost ? root.count(root.overview.cost.unpriced) : "—") }
            }
          }

          Column {
            visible: root.overview !== null && root.viewIndex === 1
            width: parent.width; spacing: Style.space(14)
            Heading { text: catalog.t("models.title") }
            RankedBars { width: parent.width; rows: root.usageData.tokens ? root.usageData.tokens.models : []; strings: catalog; limit: root.rankLimit; emptyText: catalog.t("unavailable"); unassignedText: catalog.t("unassigned") }
            Button { visible: !!root.usageData.tokens && root.usageData.tokens.models.length > root.rankLimit; text: catalog.t("more"); onClicked: root.rankLimit += 20 }
            Rule {}
            Heading { text: catalog.t("agents.title") }
            RankedBars { width: parent.width; rows: root.usageData.agents || []; strings: catalog; emptyText: catalog.t("unavailable") }
            Note { text: catalog.t("agents.note") }
            Repeater {
              model: root.usageData.agents || []
              Note {
                required property var modelData
                text: catalog.t("agents.detail").arg(modelData.name).arg(root.count(modelData.lines)).arg(root.count(modelData.sessions))
              }
            }
          }

          Column {
            visible: root.overview !== null && root.viewIndex === 2
            width: parent.width; spacing: Style.space(14)
            Row {
              width: parent.width; spacing: Style.space(5)
              Heading { text: catalog.t("projects.title"); width: parent.width - byTokens.width - byTime.width - Style.space(10); anchors.verticalCenter: parent.verticalCenter }
              Button { id: byTokens; text: catalog.t("tokens"); selected: !root.projectTime; onClicked: root.projectTime = false }
              Button { id: byTime; text: catalog.t("time"); selected: root.projectTime; onClicked: root.projectTime = true }
            }
            RankedBars { width: parent.width; rows: Model.projectRows(root.usageData.projects, root.projectTime); unit: root.projectTime ? "seconds" : "tokens"; strings: catalog; limit: root.rankLimit; unassignedText: catalog.t("unassigned"); emptyText: catalog.t("unavailable") }
            Button { visible: !!root.usageData.projects && root.usageData.projects.length > root.rankLimit; text: catalog.t("more"); onClicked: root.rankLimit += 20 }
            Note { text: catalog.t("projects.note") }
          }

          Column {
            visible: root.overview !== null && root.viewIndex === 3
            width: parent.width; spacing: Style.space(16)
            Heading { text: catalog.t("activity.title") }
            Row {
              width: parent.width
              Stat { width: parent.width / 3; title: catalog.t("trackedTime"); value: root.duration(root.time ? root.time.total_seconds : null) }
              Stat { width: parent.width / 3; title: catalog.t("dailyAverage"); value: root.usageData.breakdown ? root.duration(root.usageData.breakdown.average) : "—" }
              Stat { width: parent.width / 3; title: catalog.t("streak"); value: root.usageData.breakdown ? root.count(root.usageData.breakdown.streak) : "—" }
            }
            Heading { text: catalog.t("rhythm.title") }
            UsageHeatmap {
              width: parent.width; strings: catalog
              values: root.usageData.breakdown ? root.usageData.breakdown.agents.map(function(v, i) { return v + root.usageData.breakdown.you[i] }) : []
            }
            Note { text: catalog.t("rhythm.overlap") }
            Row {
              spacing: Style.space(3)
              Repeater {
                model: [catalog.t("languages"), catalog.t("editors"), catalog.t("categories")]
                Button { required property string modelData; required property int index; text: modelData; selected: root.activityIndex === index; onClicked: root.activityIndex = index }
              }
            }
            RankedBars { width: parent.width; rows: root.usageData.breakdown ? root.usageData.breakdown[["languages", "editors", "categories"][root.activityIndex]] : []; strings: catalog; unit: "seconds"; emptyText: catalog.t("unavailable") }
          }

          Column {
            visible: root.overview !== null && root.viewIndex === 4
            width: parent.width; spacing: Style.space(14)
            Heading { text: catalog.t("sources.title") }
            Note { text: catalog.t("sources.note") }
            Repeater {
              model: root.usageData.machines || []
              Column {
                required property var modelData
                width: body.width; spacing: Style.space(4)
                UsageText { width: parent.width; wrapMode: Text.WordWrap; text: catalog.t("machine.title").arg(modelData.name).arg(modelData.os); font.bold: true }
                Note { text: modelData.live ? catalog.t("machine.live").arg(modelData.agent) : catalog.t("machine.lastSeen").arg(root.dateLabel(modelData.last_seen)) }
              }
            }
            Rule {}
            Heading { text: catalog.t("coverage.title") }
            Repeater { model: root.overview ? root.overview.notes : []; Note { required property string modelData; text: modelData } }
            Note { visible: root.snapshot !== null && root.snapshot.errors.length > 0; text: catalog.t("sources.errors").arg(root.snapshot ? root.snapshot.errors.join(", ") : "") }
            Note { text: catalog.t("sources.refresh") }
          }
        }
      }

      Column {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        spacing: Style.space(5)
        Rule {}
        Note {
          text: root.overview ? catalog.t("footer.range").arg(root.dateLabel(root.overview.range.from)).arg(root.dateLabel(new Date(root.overview.range.to).getTime() - 1)) : catalog.t("footer.waiting")
        }
        Note {
          text: root.snapshot && root.snapshot.fetched_at ? catalog.t("footer.updated").arg(new Date(root.snapshot.fetched_at * 1000).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), "HH:mm")) : catalog.t("footer.keys")
        }
      }
    }
  }
}
