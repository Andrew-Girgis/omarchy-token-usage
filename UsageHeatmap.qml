import QtQuick
import qs.Commons
import qs.Commons as Commons

Column {
  id: root
  property var values: []
  property var strings: null
  property int hoverIndex: -1
  readonly property real maximum: Math.max.apply(null, [1].concat(values))
  readonly property var weekdays: [strings.t("mon"), strings.t("tue"), strings.t("wed"), strings.t("thu"), strings.t("fri"), strings.t("sat"), strings.t("sun")]
  spacing: Style.space(5)
  Row {
    width: parent.width
    Item { width: Style.space(38); height: 1 }
    Repeater {
      model: [0, 6, 12, 18]
      UsageText {
        required property int modelData
        width: (root.width - Style.space(38)) / 4
        text: Commons.I18n.formatNumber(modelData, 0)
        font.pixelSize: Style.font.bodySmall; opacity: 0.55
      }
    }
  }
  Repeater {
    model: 7
    Row {
      id: dayRow
      required property int index
      width: root.width
      spacing: Style.space(3)
      UsageText { width: Style.space(35); text: root.weekdays[dayRow.index]; font.pixelSize: Style.font.bodySmall; opacity: 0.7 }
      Repeater {
        model: 24
        Rectangle {
          id: cell
          required property int index
          readonly property int cellIndex: dayRow.index * 24 + index
          readonly property real seconds: root.values[cellIndex] || 0
          width: Math.max(2, (root.width - Style.space(38) - Style.space(3) * 24) / 24)
          height: Style.space(14); radius: Style.space(2)
          color: seconds > 0 ? Qt.alpha(Commons.Color.accent, Math.min(1, 0.18 + 0.82 * Math.sqrt(seconds / root.maximum))) : Qt.alpha(Commons.Color.popups.text, 0.06)
          border.width: root.hoverIndex === cellIndex ? 1 : 0
          border.color: Commons.Color.popups.text
          MouseArea {
            anchors.fill: parent; hoverEnabled: true
            onEntered: root.hoverIndex = cell.cellIndex
            onExited: root.hoverIndex = -1
          }
        }
      }
    }
  }
  UsageText {
    font.pixelSize: Style.font.bodySmall; opacity: 0.65; width: parent.width; wrapMode: Text.WordWrap
    text: root.hoverIndex < 0 ? root.strings.t("rhythm.hint") : root.strings.t("rhythm.detail")
      .arg(root.weekdays[Math.floor(root.hoverIndex / 24)])
      .arg(Commons.I18n.formatNumber(root.hoverIndex % 24, 0))
      .arg(Commons.I18n.formatNumber((root.values[root.hoverIndex] || 0) / 60, 0))
  }
}
