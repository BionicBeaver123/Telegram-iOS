import Foundation
import UIKit
import Display
import AsyncDisplayKit
import ComponentFlow
import SwiftSignalKit
import ViewControllerComponent
import ComponentDisplayAdapters
import TelegramPresentationData
import AccountContext
import TelegramCore
import MultilineTextComponent
import EmojiStatusComponent
import Postbox
import Markdown
import ContextUI
import AnimatedAvatarSetNode
import AvatarNode
import RadialStatusNode
import UndoUI
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import TelegramStringFormatting
import GalleryData
import AnimatedTextComponent

final class DataUsageScreenComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment
    
    let context: AccountContext
    let statsSet: StatsSet
    
    init(
        context: AccountContext,
        statsSet: StatsSet
    ) {
        self.context = context
        self.statsSet = statsSet
    }
    
    static func ==(lhs: DataUsageScreenComponent, rhs: DataUsageScreenComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.statsSet != rhs.statsSet {
            return false
        }
        return true
    }
    
    private final class ScrollViewImpl: UIScrollView {
        override func touchesShouldCancel(in view: UIView) -> Bool {
            return true
        }
        
        override var contentOffset: CGPoint {
            set(value) {
                /*var value = value
                if value.y > self.contentSize.height - self.bounds.height {
                    value.y = max(0.0, self.contentSize.height - self.bounds.height)
                    self.bounces = false
                } else {
                    self.bounces = true
                }*/
                super.contentOffset = value
            } get {
                return super.contentOffset
            }
        }
    }
    
    final class AnimationHint {
        enum Value {
            case modeChanged
            case clearedItems
        }
        let value: Value
        
        init(value: Value) {
            self.value = value
        }
    }
    
    struct CategoryData: Equatable {
        var incoming: Int64
        var outgoing: Int64
    }
    
    struct Stats: Equatable {
        var categories: [Category: CategoryData] = [:]
        
        init() {
        }
        
        init(stats: NetworkUsageStats, isWifi: Bool) {
            for category in Category.allCases {
                switch category {
                case .photos:
                    if isWifi {
                        self.categories[category] = CategoryData(incoming: stats.image.wifi.incoming, outgoing: stats.image.wifi.outgoing)
                    } else {
                        self.categories[category] = CategoryData(incoming: stats.image.cellular.incoming, outgoing: stats.image.cellular.outgoing)
                    }
                case .videos:
                    if isWifi {
                        self.categories[category] = CategoryData(incoming: stats.video.wifi.incoming, outgoing: stats.video.wifi.outgoing)
                    } else {
                        self.categories[category] = CategoryData(incoming: stats.video.cellular.incoming, outgoing: stats.video.cellular.outgoing)
                    }
                case .files:
                    if isWifi {
                        self.categories[category] = CategoryData(incoming: stats.file.wifi.incoming, outgoing: stats.file.wifi.outgoing)
                    } else {
                        self.categories[category] = CategoryData(incoming: stats.file.cellular.incoming, outgoing: stats.file.cellular.outgoing)
                    }
                case .music:
                    if isWifi {
                        self.categories[category] = CategoryData(incoming: stats.audio.wifi.incoming, outgoing: stats.audio.wifi.outgoing)
                    } else {
                        self.categories[category] = CategoryData(incoming: stats.audio.cellular.incoming, outgoing: stats.audio.cellular.outgoing)
                    }
                case .messages:
                    if isWifi {
                        self.categories[category] = CategoryData(incoming: stats.generic.wifi.incoming, outgoing: stats.generic.wifi.outgoing)
                    } else {
                        self.categories[category] = CategoryData(incoming: stats.generic.cellular.incoming, outgoing: stats.generic.cellular.outgoing)
                    }
                case .stickers:
                    if isWifi {
                        self.categories[category] = CategoryData(incoming: stats.sticker.wifi.incoming, outgoing: stats.sticker.wifi.outgoing)
                    } else {
                        self.categories[category] = CategoryData(incoming: stats.sticker.cellular.incoming, outgoing: stats.sticker.cellular.outgoing)
                    }
                case .voiceMessages:
                    if isWifi {
                        self.categories[category] = CategoryData(incoming: stats.voiceMessage.wifi.incoming, outgoing: stats.voiceMessage.wifi.outgoing)
                    } else {
                        self.categories[category] = CategoryData(incoming: stats.voiceMessage.cellular.incoming, outgoing: stats.voiceMessage.cellular.outgoing)
                    }
                case .calls:
                    if isWifi {
                        self.categories[category] = CategoryData(incoming: stats.call.wifi.incoming, outgoing: stats.call.wifi.outgoing)
                    } else {
                        self.categories[category] = CategoryData(incoming: stats.call.cellular.incoming, outgoing: stats.call.cellular.outgoing)
                    }
                case .totalIn, .totalOut:
                    break
                }
            }
        }
        
        var isEmpty: Bool {
            return !self.categories.values.contains(where: { $0.incoming != 0 || $0.outgoing != 0 })
        }
    }
    
    struct StatsSet: Equatable {
        var wifi: Stats
        var cellular: Stats
        var resetTimestamp: Int32
        
        init() {
            self.wifi = Stats()
            self.cellular = Stats()
            self.resetTimestamp = Int32(Date().timeIntervalSince1970)
        }
        
        init(stats: NetworkUsageStats) {
            self.wifi = Stats(stats: stats, isWifi: true)
            self.cellular = Stats(stats: stats, isWifi: false)
            self.resetTimestamp = stats.resetWifiTimestamp
        }
    }
    
    enum Category: Hashable {
        case photos
        case videos
        case files
        case music
        case messages
        case stickers
        case voiceMessages
        case calls
        case totalIn
        case totalOut
        
        static var allCases: [Category] {
            return [
                .photos,
                .videos,
                .files,
                .music,
                .messages,
                .stickers,
                .voiceMessages,
                .calls
            ]
        }
        
        var color: UIColor {
            switch self {
            case .photos:
                return UIColor(rgb: 0x5AC8FA)
            case .videos:
                return UIColor(rgb: 0x007AFF)
            case .files:
                return UIColor(rgb: 0x34C759)
            case .music:
                return UIColor(rgb: 0xFF2D55)
            case .messages:
                return UIColor(rgb: 0x5856D6)
            case .stickers:
                return UIColor(rgb: 0xFF9500)
            case .voiceMessages:
                return UIColor(rgb: 0xAF52DE)
            case .calls:
                return UIColor(rgb: 0xFF9500)
            case .totalOut:
                return UIColor(rgb: 0xFF9500)
            case .totalIn:
                return UIColor(rgb: 0xFF9500)
            }
        }
        
        var isSeparable: Bool {
            switch self {
            case .photos:
                return true
            case .videos:
                return true
            case .files:
                return true
            case .music:
                return true
            case .messages:
                return true
            case .stickers:
                return true
            case .voiceMessages:
                return true
            case .calls:
                return true
            case .totalIn, .totalOut:
                return false
            }
        }
        
        func title(strings: PresentationStrings) -> String {
            switch self {
            case .photos:
                return strings.StorageManagement_SectionPhotos
            case .videos:
                return strings.StorageManagement_SectionVideos
            case .files:
                return strings.StorageManagement_SectionFiles
            case .music:
                return strings.StorageManagement_SectionMusic
            case .messages:
                //TODO:localize
                return "Messages"
            case .stickers:
                return strings.StorageManagement_SectionStickers
            case .voiceMessages:
                return "Voice Messages"
            case .calls:
                return "Calls"
            case .totalIn:
                return "Data Received"
            case .totalOut:
                return "Data Sent"
            }
        }
    }
    
    enum SelectedStats {
        case all
        case mobile
        case wifi
    }
    
    class View: UIView, UIScrollViewDelegate {
        private let scrollView: ScrollViewImpl
        
        private var allStats: StatsSet?
        private var selectedStats: SelectedStats = .all
        private var expandedCategories: Set<Category> = Set()
        
        private let navigationBackgroundView: BlurredBackgroundView
        private let navigationSeparatorLayer: SimpleLayer
        private let navigationSeparatorLayerContainer: SimpleLayer
        
        private let headerView = ComponentView<Empty>()
        private let headerOffsetContainer: UIView
        private let headerDescriptionView = ComponentView<Empty>()
        
        private var doneStatusNode: RadialStatusNode?
        
        private let scrollContainerView: UIView
        
        private let pieChartView = ComponentView<Empty>()
        private let chartTotalLabel = ComponentView<Empty>()
        
        private let segmentedControlView = ComponentView<Empty>()
        
        private let categoriesView = ComponentView<Empty>()
        private let categoriesDescriptionView = ComponentView<Empty>()
        
        private let clearButtonView = ComponentView<Empty>()
        
        private let totalCategoriesTitleView = ComponentView<Empty>()
        private let totalCategoriesView = ComponentView<Empty>()
        
        private var component: DataUsageScreenComponent?
        private weak var state: EmptyComponentState?
        private var navigationMetrics: (navigationHeight: CGFloat, statusBarHeight: CGFloat)?
        private var controller: (() -> ViewController?)?
        
        private var enableVelocityTracking: Bool = false
        private var previousVelocityM1: CGFloat = 0.0
        private var previousVelocity: CGFloat = 0.0
        
        private var ignoreScrolling: Bool = false
        
        override init(frame: CGRect) {
            self.headerOffsetContainer = UIView()
            self.headerOffsetContainer.isUserInteractionEnabled = false
            
            self.navigationBackgroundView = BlurredBackgroundView(color: nil, enableBlur: true)
            self.navigationBackgroundView.alpha = 0.0
            
            self.navigationSeparatorLayer = SimpleLayer()
            self.navigationSeparatorLayer.opacity = 0.0
            self.navigationSeparatorLayerContainer = SimpleLayer()
            self.navigationSeparatorLayerContainer.opacity = 0.0
            
            self.scrollContainerView = UIView()
            
            self.scrollView = ScrollViewImpl()
            
            super.init(frame: frame)
            
            self.scrollView.delaysContentTouches = true
            self.scrollView.canCancelContentTouches = true
            self.scrollView.clipsToBounds = false
            if #available(iOSApplicationExtension 11.0, iOS 11.0, *) {
                self.scrollView.contentInsetAdjustmentBehavior = .never
            }
            if #available(iOS 13.0, *) {
                self.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
            }
            self.scrollView.showsVerticalScrollIndicator = false
            self.scrollView.showsHorizontalScrollIndicator = false
            self.scrollView.alwaysBounceHorizontal = false
            self.scrollView.scrollsToTop = false
            self.scrollView.delegate = self
            self.scrollView.clipsToBounds = true
            self.addSubview(self.scrollView)
            
            self.scrollView.addSubview(self.scrollContainerView)
            
            self.addSubview(self.navigationBackgroundView)
            
            self.navigationSeparatorLayerContainer.addSublayer(self.navigationSeparatorLayer)
            self.layer.addSublayer(self.navigationSeparatorLayerContainer)
            
            self.addSubview(self.headerOffsetContainer)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        deinit {
        }
        
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if !self.ignoreScrolling {
                if self.enableVelocityTracking {
                    self.previousVelocityM1 = self.previousVelocity
                    if let value = (scrollView.value(forKey: (["_", "verticalVelocity"] as [String]).joined()) as? NSNumber)?.doubleValue {
                        self.previousVelocity = CGFloat(value)
                    }
                }
                
                self.updateScrolling(transition: .immediate)
            }
        }
        
        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        }
        
        private func updateScrolling(transition: Transition) {
            let scrollBounds = self.scrollView.bounds
            
            if let headerView = self.headerView.view, let navigationMetrics = self.navigationMetrics {
                var headerOffset: CGFloat = scrollBounds.minY
                
                let minY = navigationMetrics.statusBarHeight + floor((navigationMetrics.navigationHeight - navigationMetrics.statusBarHeight) / 2.0)
                
                let minOffset = headerView.center.y - minY
                
                headerOffset = min(headerOffset, minOffset)
                
                let animatedTransition = Transition(animation: .curve(duration: 0.18, curve: .easeInOut))
                let navigationBackgroundAlpha: CGFloat = abs(headerOffset - minOffset) < 4.0 ? 1.0 : 0.0
                
                animatedTransition.setAlpha(view: self.navigationBackgroundView, alpha: navigationBackgroundAlpha)
                animatedTransition.setAlpha(layer: self.navigationSeparatorLayerContainer, alpha: navigationBackgroundAlpha)
                
                let expansionDistance: CGFloat = 32.0
                var expansionDistanceFactor: CGFloat = abs(scrollBounds.maxY - self.scrollView.contentSize.height) / expansionDistance
                expansionDistanceFactor = max(0.0, min(1.0, expansionDistanceFactor))
                
                transition.setAlpha(layer: self.navigationSeparatorLayer, alpha: expansionDistanceFactor)
                
                var offsetFraction: CGFloat = abs(headerOffset - minOffset) / 60.0
                offsetFraction = min(1.0, max(0.0, offsetFraction))
                transition.setScale(view: headerView, scale: 1.0 * offsetFraction + 0.8 * (1.0 - offsetFraction))
                
                transition.setBounds(view: self.headerOffsetContainer, bounds: CGRect(origin: CGPoint(x: 0.0, y: headerOffset), size: self.headerOffsetContainer.bounds.size))
            }
        }
        
        func update(component: DataUsageScreenComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<ViewControllerComponentContainer.Environment>, transition: Transition) -> CGSize {
            self.component = component
            self.state = state
            
            if self.allStats == nil {
                self.allStats = component.statsSet
            }
            
            let environment = environment[ViewControllerComponentContainer.Environment.self].value
            
            let animationHint = transition.userData(AnimationHint.self)
            
            if let animationHint {
                if case .clearedItems = animationHint.value {
                    /*if let snapshotView = self.scrollContainerView.snapshotView(afterScreenUpdates: false) {
                        snapshotView.frame = self.scrollContainerView.frame
                        self.scrollView.insertSubview(snapshotView, aboveSubview: self.scrollContainerView)
                        self.scrollContainerView.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                        snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                            snapshotView?.removeFromSuperview()
                        })
                    }*/
                }
            } else {
                transition.setAlpha(view: self.scrollView, alpha: 1.0)
                transition.setAlpha(view: self.headerOffsetContainer, alpha: 1.0)
            }
            
            self.controller = environment.controller
            
            self.navigationMetrics = (environment.navigationHeight, environment.statusBarHeight)
            
            self.navigationSeparatorLayer.backgroundColor = environment.theme.rootController.navigationBar.separatorColor.cgColor
            
            let navigationFrame = CGRect(origin: CGPoint(), size: CGSize(width: availableSize.width, height: environment.navigationHeight))
            self.navigationBackgroundView.updateColor(color: environment.theme.rootController.navigationBar.blurredBackgroundColor, transition: .immediate)
            self.navigationBackgroundView.update(size: navigationFrame.size, transition: transition.containedViewLayoutTransition)
            transition.setFrame(view: self.navigationBackgroundView, frame: navigationFrame)
            
            let navigationSeparatorFrame = CGRect(origin: CGPoint(x: 0.0, y: navigationFrame.maxY), size: CGSize(width: availableSize.width, height: UIScreenPixel))
            
            transition.setFrame(layer: self.navigationSeparatorLayerContainer, frame: navigationSeparatorFrame)
            transition.setFrame(layer: self.navigationSeparatorLayer, frame: CGRect(origin: CGPoint(), size: navigationSeparatorFrame.size))
            
            self.backgroundColor = environment.theme.list.blocksBackgroundColor
            
            var contentHeight: CGFloat = 0.0
            
            let topInset: CGFloat = 19.0
            let sideInset: CGFloat = 16.0 + environment.safeInsets.left
            
            let bottomInset: CGFloat = environment.safeInsets.bottom
            
            contentHeight += environment.statusBarHeight + topInset
            
            let allCategories: [Category] = [
                .photos,
                .videos,
                .files,
                .music,
                .stickers,
                .voiceMessages,
                .messages,
                .calls
            ]
            
            var listCategories: [DataCategoriesComponent.CategoryData] = []
            
            var totalSize: Int64 = 0
            var totalIn: Int64 = 0
            var totalOut: Int64 = 0
            if let allStats = self.allStats {
                var stats: Stats
                switch self.selectedStats {
                case .all:
                    stats = allStats.wifi
                    for (category, value) in allStats.cellular.categories {
                        if stats.categories[category] == nil {
                            stats.categories[category] = value
                        } else {
                            stats.categories[category]?.incoming += value.incoming
                            stats.categories[category]?.incoming += value.outgoing
                        }
                    }
                case .wifi:
                    stats = allStats.wifi
                case .mobile:
                    stats = allStats.cellular
                }
                
                for (_, value) in stats.categories {
                    totalSize += value.incoming + value.outgoing
                    totalIn += value.incoming
                    totalOut += value.outgoing
                }
                
                for category in allCategories {
                    var categoryIn: Int64 = 0
                    var categoryOut: Int64 = 0
                    if let categoryData = stats.categories[category] {
                        categoryIn = categoryData.incoming
                        categoryOut = categoryData.outgoing
                    }
                    let categorySize: Int64 = categoryIn + categoryOut
                    
                    let categoryFraction: Double
                    if categorySize == 0 || totalSize == 0 {
                        categoryFraction = 0.0
                    } else {
                        categoryFraction = Double(categorySize) / Double(totalSize)
                    }
                    
                    listCategories.append(DataCategoriesComponent.CategoryData(
                        key: category,
                        color: category.color,
                        title: category.title(strings: environment.strings),
                        size: categorySize,
                        sizeFraction: categoryFraction,
                        incoming: categoryIn,
                        outgoing: categoryOut,
                        isSeparable: category.isSeparable && (categoryIn + categoryOut != 0),
                        isExpanded: self.expandedCategories.contains(category)
                    ))
                }
            }
            
            listCategories.sort(by: { lhs, rhs in
                if lhs.size != rhs.size {
                    return lhs.size > rhs.size
                }
                return lhs.title < rhs.title
            })
            
            var chartItems: [PieChartComponent.ChartData.Item] = []
            for listCategory in listCategories {
                let categoryChartFraction: CGFloat = listCategory.sizeFraction
                chartItems.append(PieChartComponent.ChartData.Item(id: AnyHashable(listCategory.key), displayValue: listCategory.sizeFraction, displaySize: listCategory.size, value: categoryChartFraction, color: listCategory.color, particle: nil, title: listCategory.key.title(strings: environment.strings), mergeable: false, mergeFactor: 1.0))
            }
            
            if totalSize == 0 {
                chartItems.removeAll()
            }
            
            let totalCategories: [DataCategoriesComponent.CategoryData] = [
                DataCategoriesComponent.CategoryData(
                    key: .totalOut,
                    color: Category.totalOut.color,
                    title: Category.totalOut.title(strings: environment.strings),
                    size: totalOut,
                    sizeFraction: 0.0,
                    incoming: 0,
                    outgoing: 0,
                    isSeparable: false,
                    isExpanded: false
                ),
                DataCategoriesComponent.CategoryData(
                    key: .totalIn,
                    color: Category.totalIn.color,
                    title: Category.totalIn.title(strings: environment.strings),
                    size: totalIn,
                    sizeFraction: 0.0,
                    incoming: 0,
                    outgoing: 0,
                    isSeparable: false,
                    isExpanded: false
                )
            ]
            
            let chartData = PieChartComponent.ChartData(items: chartItems)
            self.pieChartView.parentState = state
            
            var pieChartTransition = transition
            if transition.animation.isImmediate, let animationHint {
                switch animationHint.value {
                case .modeChanged, .clearedItems:
                    pieChartTransition = Transition(animation: .curve(duration: 0.4, curve: .spring))
                }
            }
            
            let pieChartSize = self.pieChartView.update(
                transition: pieChartTransition,
                component: AnyComponent(PieChartComponent(
                    theme: environment.theme,
                    strings: environment.strings,
                    chartData: chartData
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: 60.0)
            )
            let pieChartFrame = CGRect(origin: CGPoint(x: 0.0, y: contentHeight), size: pieChartSize)
            if let pieChartComponentView = self.pieChartView.view {
                if pieChartComponentView.superview == nil {
                    self.scrollView.addSubview(pieChartComponentView)
                }
                
                pieChartTransition.setFrame(view: pieChartComponentView, frame: pieChartFrame)
            }
            if let allStats = self.allStats, allStats.wifi.isEmpty && allStats.cellular.isEmpty {
                let checkColor = UIColor(rgb: 0x34C759)
                
                let doneStatusNode: RadialStatusNode
                var animateIn = false
                if let current = self.doneStatusNode {
                    doneStatusNode = current
                } else {
                    doneStatusNode = RadialStatusNode(backgroundNodeColor: .clear)
                    self.doneStatusNode = doneStatusNode
                    self.scrollView.addSubnode(doneStatusNode)
                    animateIn = true
                }
                let doneSize = CGSize(width: 100.0, height: 100.0)
                doneStatusNode.frame = CGRect(origin: CGPoint(x: floor((availableSize.width - doneSize.width) / 2.0), y: contentHeight), size: doneSize)
                
                if animateIn {
                    Queue.mainQueue().after(0.18, {
                        doneStatusNode.transitionToState(.check(checkColor), animated: true)
                    })
                }
                
                contentHeight += doneSize.height
            } else {
                contentHeight += pieChartSize.height
                
                if let doneStatusNode = self.doneStatusNode {
                    self.doneStatusNode = nil
                    doneStatusNode.removeFromSupernode()
                }
            }
            
            contentHeight += 23.0
            
            let headerText: String
            if listCategories.isEmpty {
                headerText = "Data Usage Reset"
            } else {
                headerText = "Data Usage"
            }
            let headerViewSize = self.headerView.update(
                transition: transition,
                component: AnyComponent(Text(text: headerText, font: Font.semibold(20.0), color: environment.theme.list.itemPrimaryTextColor)),
                environment: {},
                containerSize: CGSize(width: floor((availableSize.width) / 0.8), height: 100.0)
            )
            let headerViewFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - headerViewSize.width) / 2.0), y: contentHeight), size: headerViewSize)
            if let headerComponentView = self.headerView.view {
                if headerComponentView.superview == nil {
                    self.headerOffsetContainer.addSubview(headerComponentView)
                }
                transition.setPosition(view: headerComponentView, position: headerViewFrame.center)
                transition.setBounds(view: headerComponentView, bounds: CGRect(origin: CGPoint(), size: headerViewFrame.size))
            }
            contentHeight += headerViewSize.height
            
            contentHeight += 6.0
            
            let body = MarkdownAttributeSet(font: Font.regular(13.0), textColor: environment.theme.list.freeTextColor)
            let bold = MarkdownAttributeSet(font: Font.semibold(13.0), textColor: environment.theme.list.freeTextColor)
            
            //TODO:localize
            
            let timestampString: String
            if let allStats = self.allStats, allStats.resetTimestamp != 0 {
                let formatter = DateFormatter()
                formatter.dateFormat = "E, d MMM yyyy HH:mm"
                let dateStringPlain = formatter.string(from: Date(timeIntervalSince1970: Double(allStats.resetTimestamp)))
                timestampString = "Your network usage since \(dateStringPlain)"
            } else {
                timestampString = "Your network usage"
            }
            
            let totalUsageText: String = timestampString
            let headerDescriptionSize = self.headerDescriptionView.update(
                transition: transition,
                component: AnyComponent(MultilineTextComponent(text: .markdown(text: totalUsageText, attributes: MarkdownAttributes(
                    body: body,
                    bold: bold,
                    link: body,
                    linkAttribute: { _ in nil }
                )), horizontalAlignment: .center, maximumNumberOfLines: 0)),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0 - 15.0 * 2.0, height: 10000.0)
            )
            let headerDescriptionFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - headerDescriptionSize.width) / 2.0), y: contentHeight), size: headerDescriptionSize)
            if let headerDescriptionComponentView = self.headerDescriptionView.view {
                if headerDescriptionComponentView.superview == nil {
                    self.scrollContainerView.addSubview(headerDescriptionComponentView)
                }
                transition.setFrame(view: headerDescriptionComponentView, frame: headerDescriptionFrame)
            }
            contentHeight += headerDescriptionSize.height
            contentHeight += 8.0
            
            contentHeight += 12.0
            
            if let allStats = self.allStats, allStats.wifi.isEmpty && allStats.cellular.isEmpty {
                if let chartTotalLabelView = self.chartTotalLabel.view {
                    chartTotalLabelView.removeFromSuperview()
                }
            } else {
                let sizeText = dataSizeString(Int(totalSize), forceDecimal: true, formatting: DataSizeStringFormatting(strings: environment.strings, decimalSeparator: "."))
                
                var animatedTextItems: [AnimatedTextComponent.Item] = []
                var remainingSizeText = sizeText
                if let index = remainingSizeText.firstIndex(of: ".") {
                    animatedTextItems.append(AnimatedTextComponent.Item(id: "n-full", content: .text(String(remainingSizeText[remainingSizeText.startIndex ..< index]))))
                    animatedTextItems.append(AnimatedTextComponent.Item(id: "dot", content: .text(".")))
                    remainingSizeText = String(remainingSizeText[remainingSizeText.index(after: index)...])
                }
                if let index = remainingSizeText.firstIndex(of: " ") {
                    animatedTextItems.append(AnimatedTextComponent.Item(id: "n-fract", content: .text(String(remainingSizeText[remainingSizeText.startIndex ..< index]))))
                    remainingSizeText = String(remainingSizeText[index...])
                }
                if !remainingSizeText.isEmpty {
                    animatedTextItems.append(AnimatedTextComponent.Item(id: "rest", isUnbreakable: true, content: .text(remainingSizeText)))
                }
                
                let chartTotalLabelSize = self.chartTotalLabel.update(
                    transition: transition,
                    component: AnyComponent(AnimatedTextComponent(
                        font: Font.with(size: 20.0, design: .round, weight: .bold),
                        color: environment.theme.list.itemPrimaryTextColor,
                        items: animatedTextItems
                    )),
                    environment: {},
                    containerSize: CGSize(width: 200.0, height: 200.0)
                )
                if let chartTotalLabelView = self.chartTotalLabel.view {
                    if chartTotalLabelView.superview == nil {
                        self.scrollContainerView.addSubview(chartTotalLabelView)
                    }
                    let totalLabelFrame = CGRect(origin: CGPoint(x: pieChartFrame.minX + floor((pieChartFrame.width - chartTotalLabelSize.width) / 2.0), y: pieChartFrame.minY + floor((pieChartFrame.height - chartTotalLabelSize.height) / 2.0)), size: chartTotalLabelSize)
                    transition.setFrame(view: chartTotalLabelView, frame: totalLabelFrame)
                    transition.setAlpha(view: chartTotalLabelView, alpha: listCategories.isEmpty ? 0.0 : 1.0)
                }
            }
            
            let segmentedSize = self.segmentedControlView.update(
                transition: transition,
                component: AnyComponent(SegmentControlComponent(
                    theme: environment.theme,
                    items: [
                        SegmentControlComponent.Item(id: AnyHashable(SelectedStats.all), title: "All"),
                        SegmentControlComponent.Item(id: AnyHashable(SelectedStats.mobile), title: "Mobile"),
                        SegmentControlComponent.Item(id: AnyHashable(SelectedStats.wifi), title: "WiFi")
                    ],
                    selectedId: "total",
                    action: { [weak self] id in
                        guard let self, let id = id.base as? SelectedStats else {
                            return
                        }
                        self.selectedStats = id
                        self.state?.updated(transition: Transition(animation: .none).withUserData(AnimationHint(value: .modeChanged)))
                    })),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 100.0)
            )
            let segmentedControlFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - segmentedSize.width) * 0.5), y: contentHeight), size: segmentedSize)
            if let segmentedControlComponentView = self.segmentedControlView.view {
                if segmentedControlComponentView.superview == nil {
                    self.scrollContainerView.addSubview(segmentedControlComponentView)
                }
                transition.setFrame(view: segmentedControlComponentView, frame: segmentedControlFrame)
            }
            contentHeight += segmentedSize.height
            contentHeight += 26.0
            
            self.categoriesView.parentState = state
            let categoriesSize = self.categoriesView.update(
                transition: transition,
                component: AnyComponent(DataCategoriesComponent(
                    theme: environment.theme,
                    strings: environment.strings,
                    categories: listCategories,
                    toggleCategoryExpanded: { [weak self] key in
                        guard let self else {
                            return
                        }
                        if self.expandedCategories.contains(key) {
                            self.expandedCategories.remove(key)
                        } else {
                            self.expandedCategories.insert(key)
                        }
                        self.state?.updated(transition: Transition(animation: .curve(duration: 0.4, curve: .spring)))
                    }
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: .greatestFiniteMagnitude)
            )
            if let categoriesComponentView = self.categoriesView.view {
                if categoriesComponentView.superview == nil {
                    self.scrollContainerView.addSubview(categoriesComponentView)
                }
                
                transition.setFrame(view: categoriesComponentView, frame: CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: categoriesSize))
            }
            contentHeight += categoriesSize.height
            contentHeight += 8.0
            
            //TODO:localize
            let categoriesDescriptionSize = self.categoriesDescriptionView.update(
                transition: transition,
                component: AnyComponent(MultilineTextComponent(text: .markdown(text: "Tap on each section for detailed view.", attributes: MarkdownAttributes(
                    body: body,
                    bold: bold,
                    link: body,
                    linkAttribute: { _ in nil }
                )), maximumNumberOfLines: 0)),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0 - 15.0 * 2.0, height: 10000.0)
            )
            let categoriesDescriptionFrame = CGRect(origin: CGPoint(x: sideInset + 15.0, y: contentHeight), size: categoriesDescriptionSize)
            if let categoriesDescriptionComponentView = self.categoriesDescriptionView.view {
                if categoriesDescriptionComponentView.superview == nil {
                    self.scrollContainerView.addSubview(categoriesDescriptionComponentView)
                }
                transition.setFrame(view: categoriesDescriptionComponentView, frame: categoriesDescriptionFrame)
            }
            contentHeight += categoriesDescriptionSize.height
            contentHeight += 40.0
            
            //TODO:localize
            let totalCategoriesTitleSize = self.totalCategoriesTitleView.update(
                transition: transition,
                component: AnyComponent(MultilineTextComponent(text: .markdown(text: "TOTAL NETWORK USAGE", attributes: MarkdownAttributes(
                    body: body,
                    bold: bold,
                    link: body,
                    linkAttribute: { _ in nil }
                )), maximumNumberOfLines: 0)),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0 - 15.0 * 2.0, height: 10000.0)
            )
            let totalCategoriesTitleFrame = CGRect(origin: CGPoint(x: sideInset + 15.0, y: contentHeight), size: totalCategoriesTitleSize)
            if let totalCategoriesTitleComponentView = self.totalCategoriesTitleView.view {
                if totalCategoriesTitleComponentView.superview == nil {
                    self.scrollContainerView.addSubview(totalCategoriesTitleComponentView)
                }
                transition.setFrame(view: totalCategoriesTitleComponentView, frame: totalCategoriesTitleFrame)
            }
            contentHeight += totalCategoriesTitleSize.height
            contentHeight += 8.0
            
            self.totalCategoriesView.parentState = state
            let totalCategoriesSize = self.totalCategoriesView.update(
                transition: transition,
                component: AnyComponent(DataCategoriesComponent(
                    theme: environment.theme,
                    strings: environment.strings,
                    categories: totalCategories,
                    toggleCategoryExpanded: { _ in
                    }
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: .greatestFiniteMagnitude)
            )
            if let totalCategoriesComponentView = self.totalCategoriesView.view {
                if totalCategoriesComponentView.superview == nil {
                    self.scrollContainerView.addSubview(totalCategoriesComponentView)
                }
                
                transition.setFrame(view: totalCategoriesComponentView, frame: CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: totalCategoriesSize))
            }
            contentHeight += totalCategoriesSize.height
            contentHeight += 40.0
            
            if let allStats = self.allStats, !(allStats.wifi.isEmpty && allStats.cellular.isEmpty) {
                let clearButtonSize = self.clearButtonView.update(
                    transition: transition,
                    component: AnyComponent(DataButtonComponent(
                        theme: environment.theme,
                        title: "Reset Statistics",
                        action: { [weak self] in
                            self?.requestClear()
                        }
                    )),
                    environment: {},
                    containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 1000.0)
                )
                let clearButtonFrame = CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: clearButtonSize)
                if let clearButtonComponentView = self.clearButtonView.view {
                    if clearButtonComponentView.superview == nil {
                        self.scrollContainerView.addSubview(clearButtonComponentView)
                    }
                    transition.setFrame(view: clearButtonComponentView, frame: clearButtonFrame)
                }
                contentHeight += clearButtonSize.height
                contentHeight += 40.0
            } else {
                if let clearButtonComponentView = self.clearButtonView.view {
                    clearButtonComponentView.isHidden = true
                }
            }
            
            contentHeight += bottomInset
            
            self.ignoreScrolling = true
            
            let contentOffset = self.scrollView.bounds.minY
            transition.setPosition(view: self.scrollView, position: CGRect(origin: CGPoint(), size: availableSize).center)
            let contentSize = CGSize(width: availableSize.width, height: contentHeight)
            if self.scrollView.contentSize != contentSize {
                self.scrollView.contentSize = contentSize
            }
            transition.setFrame(view: self.scrollContainerView, frame: CGRect(origin: CGPoint(), size: contentSize))
            
            var scrollViewBounds = self.scrollView.bounds
            scrollViewBounds.size = availableSize
            if let animationHint, case .clearedItems = animationHint.value {
                scrollViewBounds.origin.y = 0.0
            }
            transition.setBounds(view: self.scrollView, bounds: scrollViewBounds)
            
            if !pieChartTransition.animation.isImmediate && self.scrollView.bounds.minY != contentOffset {
                let deltaOffset = self.scrollView.bounds.minY - contentOffset
                pieChartTransition.animateBoundsOrigin(view: self.scrollView, from: CGPoint(x: 0.0, y: -deltaOffset), to: CGPoint(), additive: true)
                pieChartTransition.animateBoundsOrigin(view: self.headerOffsetContainer, from: CGPoint(x: 0.0, y: -deltaOffset), to: CGPoint(), additive: true)
            }
            
            self.ignoreScrolling = false
            
            self.updateScrolling(transition: transition)
            
            return availableSize
        }
        
        private func reportCleared() {
            guard let component = self.component else {
                return
            }
            guard let controller = self.controller?() else {
                return
            }
            let _ = component
            let _ = controller
            
            /*let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
            controller.present(UndoOverlayController(presentationData: presentationData, content: .succeed(text: presentationData.strings.ClearCache_Success("\(dataSizeString(size, formatting: DataSizeStringFormatting(presentationData: presentationData)))", stringForDeviceType()).string), elevatedLayout: false, action: { _ in return false }), in: .window(.root))*/
        }
        
        private func reloadStats(firstTime: Bool, completion: @escaping () -> Void) {
            guard let component = self.component else {
                completion()
                return
            }
            let _ = component
        }
        
        private func requestClear() {
            self.commitClear()
        }
        
        private func commitClear() {
            guard let component = self.component else {
                return
            }
            
            #if !DEBUG
            let _ = accountNetworkUsageStats(account: component.context.account, reset: .wifi).start()
            let _ = accountNetworkUsageStats(account: component.context.account, reset: .cellular).start()
            #endif
            
            self.allStats = StatsSet()
            //self.state?.updated(transition: Transition(animation: .none).withUserData(AnimationHint(value: .clearedItems)))
            self.state?.updated(transition: Transition(animation: .curve(duration: 0.4, curve: .spring)).withUserData(AnimationHint(value: .clearedItems)))
        }
    }
    
    func makeView() -> View {
        return View(frame: CGRect())
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<ViewControllerComponentContainer.Environment>, transition: Transition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

public final class DataUsageScreen: ViewControllerComponentContainer {
    private let context: AccountContext
    
    private let readyValue = Promise<Bool>()
    override public var ready: Promise<Bool> {
        return self.readyValue
    }
    
    fileprivate var childCompleted: ((@escaping () -> Void) -> Void)?
    
    public init(context: AccountContext, stats: NetworkUsageStats) {
        self.context = context
        
        //let componentReady = Promise<Bool>()
        super.init(context: context, component: DataUsageScreenComponent(context: context, statsSet: DataUsageScreenComponent.StatsSet(stats: stats)), navigationBarAppearance: .transparent)
        
        //self.readyValue.set(componentReady.get() |> timeout(0.3, queue: .mainQueue(), alternate: .single(true)))
        self.readyValue.set(.single(true))
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
    }
}