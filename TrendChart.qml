import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Column {
  id: root
  property var days: []
  property var strings: null
  property int hoverIndex: -1
  readonly property real maximum: Model.maxValue(days)
  spacing: Style.space(6)

  Item {
    width: parent.width; height: Style.space(110)
    Row {
      anchors.fill: parent
      spacing: Style.space(3)
      Repeater {
        model: root.days
        delegate: Item {
          required property var modelData
          required property int index
          width: Math.max(1, (root.width - Math.max(0, root.days.length - 1) * Style.space(3)) / Math.max(1, root.days.length))
          height: parent.height
          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: modelData.value > 0 ? Math.max(2, parent.height * modelData.value / root.maximum) : 1
            radius: Math.min(3, width / 3)
            color: root.hoverIndex === index ? Commons.Color.popups.text : Commons.Color.accent
            opacity: modelData.value > 0 ? 0.85 : 0.15
          }
          MouseArea {
            anchors.fill: parent; hoverEnabled: true
            onEntered: root.hoverIndex = index
            onExited: root.hoverIndex = -1
          }
        }
      }
    }
  }
  UsageText {
    width: parent.width; opacity: 0.7
    font.pixelSize: Style.font.bodySmall
    text: {
      if (!root.days.length) return root.strings.t("empty.tokens")
      var d = root.days[root.hoverIndex >= 0 ? root.hoverIndex : root.days.length - 1]
      var date = d.date === d.end ? d.date : root.strings.t("dateSpan").arg(d.date).arg(d.end)
      return root.strings.t("trend.detail").arg(date).arg(Commons.I18n.formatNumber(d.value, 0))
    }
  }
}
