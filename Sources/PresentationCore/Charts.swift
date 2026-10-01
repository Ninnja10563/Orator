import Foundation

public struct ChartSeries: Codable, Equatable, Sendable {
    public var name: String
    public var values: [Double]
    public var color: RGBA?
    public init(name: String,values: [Double],color: RGBA? = nil) { self.name=name; self.values=values; self.color=color }
}
public extension ChartContent {
    var dataSeries: [ChartSeries] { series?.isEmpty == false ? series! : [ChartSeries(name:"Series 1",values:values)] }
    mutating func setSeries(_ value: [ChartSeries]) { series=value; values=value.first?.values ?? [] }
    mutating func insertCategory() { guard labels.count < 10000 else { return }; labels.append("Category \(labels.count+1)"); var data=dataSeries; for i in data.indices { data[i].values.append(0) }; setSeries(data) }
    mutating func removeCategory(at index: Int) { guard labels.count > 1, labels.indices.contains(index) else { return }; labels.remove(at:index); var data=dataSeries; for i in data.indices { data[i].values.remove(at:index) }; setSeries(data) }
}
