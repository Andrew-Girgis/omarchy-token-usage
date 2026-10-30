import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Column {
  id: root
  property var rows: []
  property string unit: "tokens"
  property int limit: 12
  property string emptyText: ""
  property string unassignedText: ""
  property var strings: null
  readonly property real maximum: Model.maxValue(rows)
  spacing: Style.space(10)

  function valueText(value) {
    if (unit === "seconds") {
      var parts = Model.timeParts(value)
      return strings.t("duration").arg(Commons.I18n.formatNumber(parts[0])).arg(Commons.I18n.formatNumber(parts[1]))
    }
    return Commons.I18n.formatNumber(value, 0)
  }

  Repeater {
    model: root.rows.slice(0, root.limit)
    delegate: Column {
      required property var modelData
      width: root.width
      spacing: Style.space(4)
      Row {
        width: parent.width
        UsageText {
          width: parent.width - amount.implicitWidth - Style.space(10)
          text: modelData.name || root.unassignedText
          elide: Text.ElideRight
        }
        UsageText { id: amount; text: root.valueText(modelData.value); opacity: 0.75 }
      }
      Rectangle {
        width: parent.width; height: Style.space(4); radius: height / 2
        color: Qt.alpha(Commons.Color.popups.text, 0.08)
        Rectangle {
          width: parent.width * Math.min(1, modelData.value / root.maximum)
          height: parent.height; radius: height / 2
          color: Commons.Color.accent
        }
      }
    }
  }
  UsageText { visible: root.rows.length === 0; text: root.emptyText; opacity: 0.65; width: parent.width; wrapMode: Text.WordWrap }
}
