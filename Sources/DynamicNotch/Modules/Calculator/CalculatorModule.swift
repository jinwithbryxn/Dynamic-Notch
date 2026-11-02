import AppKit
import SwiftUI

/// 계산기·단위 변환·환율 변환 탭과 팔레트 즉석 결과.
/// 환율은 설정에서 켠 경우에만, 통화 변환식을 입력했을 때 frankfurter.app에서 받는다 (12시간 보관).
final class CalculatorModule: NotchModule {
    let id = "calculator"
    var title: String { T("계산기", "Calculator") }
    let symbol = "plus.forwardslash.minus"
    var enabledByDefault: Bool { true }

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    fileprivate var context: ModuleContext?

    /// 환율 받기 허용 (기본 꺼짐: 네트워크)
    var currencyEnabled: Bool { defaults.bool("currency", default: false) }
    func setCurrencyEnabled(_ on: Bool) { defaults.set(on, "currency") }

    func start(context: ModuleContext) { self.context = context }
    func stop() {
        CurrencyRates.shared.cancel()
        context = nil
    }

    func tabView() -> AnyView? { AnyView(CalculatorTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 460, height: 250) }

    func settingsView() -> AnyView? { AnyView(CalculatorSettings(module: self)) }

    // MARK: 기록·직전 답 (설정이 아니라 데이터라 알림 없이 저장)

    struct Entry: Codable, Hashable { let expr: String; let result: String }

    var history: [Entry] {
        guard let d = UserDefaults.standard.data(forKey: "module.calculator.history"),
              let list = try? JSONDecoder().decode([Entry].self, from: d) else { return [] }
        return list
    }
    var ans: Double? { UserDefaults.standard.object(forKey: "module.calculator.ans") as? Double }

    func record(_ expr: String, result: String, value: Double?) {
        var list = history.filter { $0.expr != expr }
        list.insert(Entry(expr: expr, result: result), at: 0)
        if let d = try? JSONEncoder().encode(Array(list.prefix(30))) { UserDefaults.standard.set(d, forKey: "module.calculator.history") }
        if let value { UserDefaults.standard.set(value, forKey: "module.calculator.ans") }
    }

    func clearHistory() { UserDefaults.standard.removeObject(forKey: "module.calculator.history") }

    // MARK: 계산

    struct Answer {
        var text: String          // 화면에 보일 답
        var copy: String          // 복사할 값
        var value: Double?
        var note: String? = nil   // 환율 기준 등
        var needsCurrencyConsent = false
        var pending = false
    }

    /// 입력에 대한 답. 통화식이고 환율이 없으면 받기를 시작한다 (허용된 경우만).
    func answer(for raw: String, fetch: Bool, onRates: (() -> Void)? = nil) -> Answer? {
        let input = raw.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return nil }
        if let q = UnitConvert.parse(input, ans: ans) {
            if q.isCurrency {
                guard currencyEnabled else {
                    return Answer(text: "\(q.from) → \(q.to)", copy: "", value: nil,
                                  note: T("환율 변환은 설정에서 켜야 함 (frankfurter.app에서 받음)", "Currency conversion is off (rates come from frankfurter.app)"),
                                  needsCurrencyConsent: true)
                }
                let rates = CurrencyRates.shared
                if !rates.isFresh, fetch { rates.refreshIfNeeded(done: onRates) }
                if let v = rates.convert(q.amount, from: q.from, to: q.to) {
                    let text = CalcEngine.format(v) + " " + q.to
                    return Answer(text: text, copy: CalcEngine.format(v, grouping: false), value: v, note: rates.statusText)
                }
                return Answer(text: "\(q.from) → \(q.to)", copy: "", value: nil, note: rates.statusText, pending: rates.loading)
            }
            if let v = UnitConvert.convert(q) {
                return Answer(text: CalcEngine.format(v) + " " + UnitConvert.symbol(q.to),
                              copy: CalcEngine.format(v, grouping: false), value: v,
                              note: "\(CalcEngine.format(q.amount)) \(UnitConvert.symbol(q.from))")
            }
        }
        if let v = CalcEngine.evaluate(input, ans: ans) {
            return Answer(text: CalcEngine.format(v), copy: CalcEngine.format(v, grouping: false), value: v)
        }
        return nil
    }

    func paletteResults(for query: String) -> [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard UnitConvert.parse(q, ans: ans) != nil || CalcEngine.looksLikeMath(q) else { return [] }
        guard let a = answer(for: q, fetch: true) else { return [] }
        if a.needsCurrencyConsent {
            return [PaletteAction(id: "calculator.currency.enable", title: T("환율 변환 켜기", "Turn on currency conversion"),
                                  subtitle: a.note, symbol: "dollarsign.arrow.circlepath") { [weak self] in
                self?.setCurrencyEnabled(true)
                CurrencyRates.shared.refreshIfNeeded()
            }]
        }
        guard a.value != nil else {
            return [PaletteAction(id: "calculator.pending", title: a.text, subtitle: a.note, symbol: "hourglass", run: {})]
        }
        return [PaletteAction(id: "calculator.result", title: "= " + a.text,
                              subtitle: (a.note.map { $0 + " · " } ?? "") + T("Return: 복사", "Return: copy"),
                              symbol: symbol) { [weak self] in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(a.copy, forType: .string)
            self?.record(q, result: a.text, value: a.value)
        }]
    }

    func selfTest() -> [String] {
        var out: [String] = []
        let samples: [(String, Double?)] = [
            ("1+2*3", 7), ("(1+2)*3", 9), ("2^10", 1024), ("200 + 10%", 220), ("200 - 10%", 180), ("10% * 200", 20),
            ("sqrt(16)", 4), ("2pi", 2 * .pi), ("sin(90°)", 1), ("log(1000)", 3), ("log(8, 2)", 3), ("5!", 120),
            ("1,000 * 3", 3000), ("max(1, 7, 3)", 7), ("round(3.14159, 2)", 3.14), ("10 mod 3", 1), ("-3^2", -9),
            ("1/0", nil), ("2 +", nil), ("((((1", nil), ("foo(2)", nil), ("1e3 + 1", 1001),
        ]
        var pass = 0
        for (expr, want) in samples {
            let got = CalcEngine.evaluate(expr)
            let ok: Bool = {
                switch (got, want) {
                case (nil, nil): return true
                case let (g?, w?): return abs(g - w) < 1e-9 * max(1, abs(w))
                default: return false
                }
            }()
            if ok { pass += 1 }
            out.append("\(ok ? "ok  " : "FAIL") \(expr) = \(got.map { CalcEngine.format($0) } ?? "error")")
        }
        out.append("ans: \(CalcEngine.evaluate("ans * 2", ans: 21).map { CalcEngine.format($0) } ?? "error") (ans=21)")
        // 긴 입력·깊은 괄호에도 죽지 않는지
        out.append("deep parens: \(CalcEngine.evaluate(String(repeating: "(", count: 300) + "1" + String(repeating: ")", count: 300)) == nil ? "rejected" : "evaluated")")
        out.append("long input: \(CalcEngine.evaluate(String(repeating: "1+", count: 300) + "1") == nil ? "rejected" : "evaluated")")
        let convs: [(String, Double)] = [
            ("90 f to c", 32.2222222222), ("100 c in f", 212), ("5 km to mi", 3.10685596), ("1 lb in g", 453.59237),
            ("12 in to cm", 30.48), ("1 gb to mb", 1000), ("60 mph to km/h", 96.56064), ("2+3 kg to lb", 11.0231131),
            ("1 atm to kpa", 101.325), ("30 평 to m2", 99.17355), ("90 deg to rad", .pi / 2), ("1500 ms to sec", 1.5),
        ]
        for (expr, want) in convs {
            let q = UnitConvert.parse(expr)
            let got = q.flatMap { UnitConvert.convert($0) }
            let ok = got.map { abs($0 - want) < 1e-4 * max(1, abs(want)) } ?? false
            if ok { pass += 1 }
            out.append("\(ok ? "ok  " : "FAIL") \(expr) = \(got.map { CalcEngine.format($0) } ?? "error")")
        }
        for expr in ["50 usd in eur", "$20 to krw", "1000 엔 to 원", "10 eur to usd"] {
            if let q = UnitConvert.parse(expr), q.isCurrency {
                pass += 1
                out.append("ok   \(expr) -> currency \(q.amount) \(q.from)→\(q.to) (fetch skipped in self test)")
            } else { out.append("FAIL \(expr) not parsed as currency") }
        }
        out.append("not convertible: \(UnitConvert.parse("5 km to kg") == nil ? "ok (km→kg rejected)" : "FAIL")")
        let r = CurrencyRates.shared
        out.append("currency setting: \(currencyEnabled ? "on" : "off"); cached rates: \(r.rates.count) (\(r.statusText))")
        for q in ["2+2*3", "90 f to c", "hello", "42"] {
            out.append("palette \"\(q)\": " + (paletteResults(for: q).first.map { $0.title } ?? "(none)"))
        }
        out.append("passed \(pass)/\(samples.count + convs.count + 4)")
        return out
    }
}

// MARK: - 탭 화면

private final class CalcModel: ObservableObject {
    @Published var input = ""
    @Published var tick = 0
}

private struct CalculatorTab: View {
    let module: CalculatorModule
    @StateObject private var model = CalcModel()
    @FocusState private var focused: Bool
    @State private var history: [CalculatorModule.Entry] = []
    @State private var copied = false

    private var answer: CalculatorModule.Answer? {
        _ = model.tick
        return module.answer(for: model.input, fetch: true) { model.tick += 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LaunchField(placeholder: T("식 또는 변환 (예: 200+10%, 90 f to c, 50 usd in eur)", "Expression or conversion (200+10%, 90 f to c, 50 usd in eur)"),
                        text: $model.input, symbol: "equal.square", focus: $focused, onSubmit: confirm)
            answerView
            Divider().overlay(Color.white.opacity(0.08))
            historyView
        }
        .foregroundStyle(.white)
        .onAppear {
            history = module.history
            module.context?.focusInput()
            DispatchQueue.main.async { focused = true }
        }
    }

    @ViewBuilder private var answerView: some View {
        let a = answer
        VStack(alignment: .trailing, spacing: 2) {
            HStack {
                if let a, a.needsCurrencyConsent {
                    LaunchChip(title: T("환율 받기 켜기", "Allow rate fetch"), symbol: "network") {
                        module.setCurrencyEnabled(true)
                        model.tick += 1
                    }
                }
                Spacer()
                Text(a.map { $0.value != nil ? "= " + $0.text : $0.text } ?? (model.input.isEmpty ? " " : "…"))
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(a?.value != nil ? Color.white : LaunchUI.secondary)
                    .textSelection(.enabled)
            }
            Text(copied ? T("복사함", "Copied") : (a?.note ?? T("Return: 확정·복사 · ans = 직전 답", "Return: confirm & copy · ans = last answer")))
                .font(.system(size: 10.5)).foregroundStyle(LaunchUI.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder private var historyView: some View {
        if history.isEmpty {
            Text(T("기록 없음", "No history"))
                .font(.system(size: 11)).foregroundStyle(LaunchUI.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(history, id: \.self) { e in
                        Button { model.input = e.expr } label: {
                            HStack {
                                Text(e.expr).lineLimit(1).foregroundStyle(LaunchUI.secondary)
                                Spacer()
                                Text(e.result).lineLimit(1).monospacedDigit()
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                        .help(T("다시 입력", "Reuse"))
                    }
                }
            }
        }
    }

    private func confirm() {
        guard let a = answer, a.value != nil else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(a.copy, forType: .string)
        module.record(model.input.trimmingCharacters(in: .whitespaces), result: a.text, value: a.value)
        history = module.history
        model.input = ""
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

private struct CalculatorSettings: View {
    let module: CalculatorModule
    @State private var currency = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(T("환율 변환 (frankfurter.app에서 ECB 환율을 받음)", "Currency conversion (fetches ECB rates from frankfurter.app)"), isOn: $currency)
                .onChange(of: currency) { _, v in module.setCurrencyEnabled(v) }
            Text(T("통화 변환식을 입력했을 때만 받고 12시간 보관합니다. 입력한 금액은 보내지 않습니다.",
                   "Rates are fetched only when you type a currency conversion and kept for 12 hours. Amounts are never sent."))
                .font(.caption).foregroundStyle(.secondary)
            Button(T("계산 기록 지우기", "Clear history")) { module.clearHistory() }
        }
        .onAppear { currency = module.currencyEnabled }
    }
}
