import SwiftUI
import MapGrapherCore

/// 今日（ホーム）。Androidの今日と同じく、同じ角丸の箱を並べず、エリアごとに形を変える。斜めの辺はどれも同じ向き（＼）にそろえる。
/// 見出し → 今日のお題（右端から出てくる台形）→ 今週のあしあと（箱なし。のこした日だけインクのハンコ）
/// → グループのお題（左端から出てくる台形）→ 近くの痕跡とフレンド（画面幅の帯を斜めに2つに割る）
@MainActor
struct TodayScreen: View {
    let onOpenTab: (AppRoute.Tab) -> Void
    let onPresentRoute: (AppRoute) -> Void
    @StateObject private var model: TodayScreenModel
    @State private var appeared = false

    private let slant: CGFloat = 28
    private static let weekColors: [Color] = [
        AppColors.shu, AppColors.fuji, AppColors.yellow, AppColors.sky,
        AppColors.lime, AppColors.shu, AppColors.fuji
    ]

    init(groupsService: any GroupsServing = FakeGroupsServing(),
         context: SessionContext? = nil,
         groupsDataMode: GroupUIDataMode = .fake,
         socialService: any SocialProfileUIService = FakeSocialProfileUIService(),
         footprints: any TodayFootprintReading = FakeTodayFootprintReader(),
         onOpenTab: @escaping (AppRoute.Tab) -> Void,
         onPresentRoute: @escaping (AppRoute) -> Void) {
        self.onOpenTab = onOpenTab
        self.onPresentRoute = onPresentRoute
        _model = StateObject(wrappedValue: TodayScreenModel(
            groupsService: groupsService, context: context, groupsDataMode: groupsDataMode,
            socialService: socialService, footprints: footprints
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                missionZone
                    .padding(.top, AppSpacing.xLarge)
                    .offset(x: appeared ? 0 : 420)
                weekSection
                    .padding(.top, 28)
                groupZone
                    .padding(.top, 28)
                    .offset(x: appeared ? 0 : -420)
                tilesBand
                    .padding(.top, 20)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, AppSpacing.medium)
            .padding(.bottom, AppSpacing.xLarge)
        }
        .scrollClipDisabled()
        .background(AppColors.paper.ignoresSafeArea())
        .task {
            await model.load()
        }
        .onAppear {
            // 開いたとき、お題は右から、グループは左から滑り込み、帯は下から浮かぶ
            guard !appeared else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86).delay(0.06)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.today")
        .accessibilityLabel(Text(AppStrings.today))
    }

    // MARK: 見出し：日付・「今日を残す」・あいさつ・自分の画面への入口

    private var header: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ja_JP")))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppColors.shuEdge)
                (Text("today.title.today").foregroundStyle(AppColors.shu) + Text("today.title.rest"))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.ink)
                    .accessibilityAddTraits(.isHeader)
                greeting
                    .font(.subheadline)
                    .foregroundStyle(AppColors.muted)
            }
            Spacer(minLength: 0)
            Button {
                onOpenTab(.profile)
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(AppColors.fuji)
                    .frame(width: 58, height: 58)
                    .background(AppColors.surface, in: Circle())
                    .overlay { Circle().stroke(AppColors.yellow, lineWidth: 3) }
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            }
            .buttonStyle(PressableScaleStyle())
            .accessibilityLabel(Text(AppStrings.profile))
            .accessibilityIdentifier("today.profile")
        }
    }

    private var greeting: Text {
        let name = model.displayName ?? String(localized: "today.guest")
        switch Calendar.current.component(.hour, from: .now) {
        case 4...10: return Text("today.greeting.morning \(name)")
        case 11...17: return Text("today.greeting.day \(name)")
        default: return Text("today.greeting.night \(name)")
        }
    }

    // MARK: 今日のお題：右の画面端から出てくる藤の台形（画面の主役）

    private var missionZone: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("today.mission.label")
                .font(.footnote.weight(.bold))
            Text("today.mission.body")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 70)
            Button {
                onPresentRoute(.postComposer)
            } label: {
                Label("today.mission.action", systemImage: "camera.fill")
            }
            .buttonStyle(RakugakiPrimaryButtonStyle())
            .padding(.top, AppSpacing.medium)
            .accessibilityIdentifier("today.mission.camera")
        }
        .foregroundStyle(AppColors.onAccent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 40)
        .padding(.top, 36)
        .padding(.trailing, AppSpacing.xLarge + 20)
        .padding(.bottom, 20)
        .background {
            SlantShape(insetBottomLeft: slant, radiusTopLeft: 22, radiusBottomLeft: 22)
                .fill(AppColors.fuji)
                .shadow(color: AppColors.fujiEdge.opacity(0.35), radius: 10, y: 6)
        }
        .overlay(alignment: .topLeading) {
            deadlineBadge
                .rotationEffect(.degrees(-6))
                .offset(x: 28, y: -10)
        }
        .overlay(alignment: .bottomTrailing) {
            photoFrame
                .padding(.trailing, 44)
                .padding(.bottom, 18)
        }
        .padding(.leading, -8)
        .padding(.trailing, -20)
    }

    private var deadlineBadge: some View {
        Group {
            if let hours = TodayWeek.hoursLeft(now: .now, calendar: .current) {
                Text("today.mission.deadline \(hours)")
            } else {
                Text("today.mission.deadline.soon")
            }
        }
        .font(.footnote.weight(.bold))
        .foregroundStyle(AppColors.onAccent)
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, 4)
        .background(AppColors.yellow, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        .accessibilityIdentifier("today.mission.deadline")
    }

    // 右下に少し傾けた写真の枠（＋7度）。押すとお題の写真を撮る。開いたときは回しながらぺたっと貼る
    private var photoFrame: some View {
        Button {
            onPresentRoute(.postComposer)
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 22))
                .foregroundStyle(AppColors.fuji)
                .frame(width: 66, height: 64)
                .background(AppColors.fujiTint, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(AppColors.fuji, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 20)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
        }
        .buttonStyle(PressableScaleStyle())
        .rotationEffect(.degrees(appeared ? 7 : -14))
        .scaleEffect(appeared ? 1 : 0.01)
        .animation(.spring(response: 0.42, dampingFraction: 0.55).delay(0.44), value: appeared)
        .accessibilityLabel(Text("today.mission.action"))
        .accessibilityIdentifier("today.mission.photo-frame")
    }

    // MARK: 今週のあしあと：箱に入れず地に直接並べる。のこした日だけインクのハンコ

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                Text("today.week.title")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.ink)
                if model.footprintsArePrototype {
                    PrototypeBadge()
                }
                Spacer(minLength: 0)
                Group {
                    if model.postedCount > 0 {
                        Text("today.week.summary \(model.postedCount)")
                    } else {
                        Text("today.week.empty")
                    }
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(AppColors.shuEdge)
            }
            HStack(spacing: 0) {
                ForEach(model.week) { day in
                    dayCell(day)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.week")
    }

    private func dayCell(_ day: TodayWeekDay) -> some View {
        let label = Self.weekdayLabel(day.index)
        return VStack(spacing: 4) {
            ZStack {
                switch day.status {
                case .posted:
                    InkSplatView(seed: 30 + day.index, color: Self.weekColors[day.index],
                                 splashKey: day.date, animated: day.isToday)
                case .today:
                    Circle()
                        .strokeBorder(AppColors.shu, lineWidth: 2)
                        .background(Circle().fill(AppColors.surface))
                        .frame(width: 36, height: 36)
                case .past, .future:
                    EmptyView()
                }
                Text("\(day.dayOfMonth)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(day.status == .posted ? AppColors.onAccent
                                     : day.status == .today ? AppColors.shuEdge : AppColors.muted)
            }
            .frame(width: 46, height: 40)
            .opacity(day.status == .future ? 0.45 : 1)
            Text(label)
                .font(.caption2.weight(day.isToday ? .bold : .regular))
                .foregroundStyle(day.isToday ? AppColors.shuEdge : AppColors.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.status == .posted ? Text("today.week.day.posted \(label)")
                            : Text("today.week.day.empty \(label)"))
    }

    private static func weekdayLabel(_ index: Int) -> String {
        ["月", "火", "水", "木", "金", "土", "日"][index]
    }

    // MARK: グループのお題：左の画面端から出てくる淡い朱の台形。お題は吹き出し、回答は丸で並べる

    private var groupZone: some View {
        Button {
            onOpenTab(.groups)
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                HStack(spacing: AppSpacing.small) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.onAccent)
                        .frame(width: 36, height: 36)
                        .background(AppColors.fuji, in: Circle())
                    groupTitle
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppColors.ink)
                        .lineLimit(1)
                    if model.groupsDataMode == .fake {
                        PrototypeBadge()
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppColors.shuEdge)
                        .frame(width: 32, height: 32)
                        .background(AppColors.surface, in: Circle())
                }
                groupPrompt
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColors.ink)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, AppSpacing.large)
                    .padding(.vertical, AppSpacing.small)
                    .background(SpeechBubble().fill(AppColors.surface))
                HStack(spacing: AppSpacing.small) {
                    if let group = model.group {
                        answerDots(answered: Int(group.answeredCount), total: Self.total(group))
                    }
                    groupMeta
                        .font(.footnote)
                        .foregroundStyle(AppColors.muted)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 36)
            .padding(.trailing, 44)
            .padding(.vertical, AppSpacing.large)
            .background {
                SlantShape(insetTopRight: slant, radiusTopRight: 22, radiusBottomRight: 22)
                    .fill(AppColors.shuTint)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
        }
        .buttonStyle(PressableScaleStyle())
        .padding(.leading, -20)
        .padding(.trailing, AppSpacing.small)
        .accessibilityIdentifier("today.group")
    }

    private var groupTitle: Text {
        if let group = model.group { return Text("today.group.title \(group.name)") }
        return Text("today.group.empty.title")
    }

    private var groupPrompt: Text {
        guard let group = model.group else { return Text("today.group.empty.prompt") }
        if let prompt = group.promptText?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            return Text(verbatim: "「\(prompt)」")
        }
        return Text("today.group.prompt.unset")
    }

    private var groupMeta: Text {
        guard let group = model.group else { return Text("today.group.empty.meta") }
        let answered = Int(group.answeredCount)
        let total = Self.total(group)
        return group.hasAnswered ? Text("today.group.answered \(answered) \(total)")
            : Text("today.group.progress \(answered) \(total)")
    }

    private static func total(_ group: GroupSummary) -> Int {
        Int(group.participantCount > 0 ? group.participantCount : group.memberCount)
    }

    // 回答した人は朱で塗り、まだの人は輪だけにする（最大8人）
    private func answerDots(answered: Int, total: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<min(total, 8), id: \.self) { index in
                Circle()
                    .fill(index < answered ? AppColors.shu : AppColors.surface)
                    .overlay { Circle().strokeBorder(AppColors.shu, lineWidth: 2) }
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: 近くの痕跡とフレンド：画面幅の帯を斜めに2つに割る（左は水色、右は黄緑）

    private var tilesBand: some View {
        HStack(alignment: .top, spacing: -(slant - 6)) {
            tile(icon: "mappin", iconColor: AppColors.sky, title: "today.nearby.title",
                 detail: "today.nearby.body", identifier: "today.nearby",
                 shape: SlantShape(insetTopRight: slant, radiusTopRight: 14, radiusBottomRight: 14),
                 fill: AppColors.skyTint, leading: 20, trailing: 36) {
                onOpenTab(.map)
            }
            tile(icon: "person.fill", iconColor: AppColors.lime, title: "today.friends.title",
                 detail: "today.friends.body", identifier: "today.friends",
                 shape: SlantShape(insetBottomLeft: slant, radiusTopLeft: 14, radiusBottomLeft: 14),
                 fill: AppColors.limeTint, leading: 44, trailing: 20) {
                onOpenTab(.profile)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, -20)
    }

    private func tile(icon: String, iconColor: Color, title: LocalizedStringKey, detail: LocalizedStringKey,
                      identifier: String, shape: SlantShape, fill: Color,
                      leading: CGFloat, trailing: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.onAccent)
                    .frame(width: 40, height: 40)
                    .background(iconColor, in: Circle())
                    .padding(.bottom, AppSpacing.medium - 2)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppColors.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.vertical, AppSpacing.large)
            .background {
                shape.fill(fill).shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityIdentifier(identifier)
    }
}

/// しっぽ付きの吹き出し（左下にしっぽ）
private struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 16, style: .continuous)
        path.move(to: CGPoint(x: rect.minX + 22, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.minX + 30, y: rect.maxY + 8))
        path.addLine(to: CGPoint(x: rect.minX + 38, y: rect.maxY - 1))
        path.closeSubpath()
        return path
    }
}

/// サーバーにつながっていない部分に付ける「試作」の札
struct PrototypeBadge: View {
    var body: some View {
        Text(AppStrings.prototypeBadge)
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppColors.shuEdge)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(AppColors.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(AppColors.shu, lineWidth: 1) }
            .accessibilityIdentifier("prototype.badge")
    }
}
