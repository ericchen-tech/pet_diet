import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:fl_chart/fl_chart.dart';

void main() => runApp(const PetDietApp());

class PetDietApp extends StatelessWidget {
  const PetDietApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI 寵物營養分析',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const DietScreen(),
    );
  }
}

class DietScreen extends StatefulWidget {
  const DietScreen({super.key});
  @override
  State<DietScreen> createState() => _DietScreenState();
}

class _DietScreenState extends State<DietScreen> {
  String _userApiKey = '';
  bool _isLoading = false;
  Map<String, dynamic>? _nutritionData;
  List<dynamic> _topIngredients = [];
  String _deepAnalysisText = ""; // 儲存診斷文字的變數

  double _totalPrice = 0.0;
  double _inputWeight = 1.0;
  String _weightUnit = 'kg';

  double _petWeight = 5.0;
  bool _isCat = true;
  double _factor = 1.2;
  bool _isDMB = false;
  double _wetFoodRatio = 0.5;

  final Map<String, double> _catFactors = {
    "已結紮成貓 (1.2)": 1.2,
    "未結紮成貓 (1.4)": 1.4,
    "需減重貓 (1.0)": 1.0,
    "肥胖傾向 (0.8)": 0.8,
  };
  final Map<String, double> _dogFactors = {
    "已結紮成犬 (1.6)": 1.6,
    "未結紮成犬 (1.8)": 1.8,
    "高運動量犬 (2.5)": 2.5,
    "肥胖傾向 (1.2)": 1.2,
  };

  Future<void> _analyzeMultiImages() async {
    if (_userApiKey.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("⚠️ 請在上方輸入您的 API Key")));
      return;
    }
    final picker = ImagePicker();
    final List<XFile> pickedImages = await picker.pickMultiImage();
    if (pickedImages.isEmpty) return;

    setState(() {
      _isLoading = true;
      _nutritionData = null;
      _deepAnalysisText = ""; // 點擊按鈕時先清空舊文字
    });

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _userApiKey.trim(),
      );

      List<DataPart> imageParts = [];
      for (var img in pickedImages.take(2)) {
        final bytes = await img.readAsBytes();
        imageParts.add(DataPart('image/jpeg', bytes));
      }

      // 強化 Prompt 確保 AI 一定會產出報告文字
      final prompt = """
      你現在是專業寵物營養師，請辨識照片中的數據並回傳 JSON 格式。
      要求：
      1. 數據：protein, fat, fiber, moisture, ash, calcium, phosphorus。
      2. 診斷報告：請在 "deep_analysis" 欄位寫下超過 200 字的深度成分分析。
      JSON 格式範例：
      {
        "protein": 33, "fat": 12, "fiber": 5, "moisture": 9, "ash": 0, 
        "calcium": 0.8, "phosphorus": 0.7,
        "ingredients": [{"name": "雞肉", "quality": "good", "reason": "鮮肉來源"}],
        "deep_analysis": "在此輸入長篇診斷內容..."
      }
      """;

      final response = await model.generateContent([
        Content.multi([TextPart(prompt), ...imageParts]),
      ]);
      String cleanJson = (response.text ?? "")
          .replaceAll(RegExp(r'```json|```'), '')
          .trim();
      final data = jsonDecode(cleanJson);

      setState(() {
        _nutritionData = data;
        _topIngredients = data['ingredients'] ?? [];
        // 關鍵修正：確保這裡有抓到 AI 的診斷欄位
        _deepAnalysisText = data['deep_analysis'] ?? "AI 未能產出報告文字，請重新上傳照片。";
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      // 若遇到 Quota 錯誤會在此顯示
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("分析失敗，可能是配額限制，請稍候再試：$e")));
    }
  }

  double _calculatePricePerKg() {
    double weightInKg = (_weightUnit == 'lb')
        ? _inputWeight * 0.4536
        : (_weightUnit == 'g')
        ? _inputWeight / 1000
        : _inputWeight;
    return weightInKg <= 0 ? 0 : _totalPrice / weightInKg;
  }

  double _safeNum(String key) {
    if (_nutritionData == null || _nutritionData![key] == null) return 0.0;
    var val = _nutritionData![key];
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString().replaceAll(RegExp(r'[^0-9.]'), '')) ??
        0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI 寵物營養分析"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSecurityPanel(),
            _buildSpeciesToggle(),
            _buildPriceWeightInput(),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _analyzeMultiImages,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_isLoading ? "分析中..." : "上傳照片"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
            if (_nutritionData != null) ...[
              const SizedBox(height: 15),
              _buildDeepAnalysisCard(), // [AI 成分診斷] 收合區
              const SizedBox(height: 15),
              _buildDMBToggle(),
              _buildHorizontalAnalysisPanel(),
              _buildCPValueRow(),
              _buildHealthAlerts(),
              _buildIngredientExpansion(),
              _buildFeedingCalculator(),
            ],
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(50),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeepAnalysisCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.fact_check, color: Colors.teal),
        title: const Text(
          "[AI 成分診斷]",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
        ),
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            // ✅ 顯示變數文字，確保不會空白
            child: Text(
              _deepAnalysisText.isEmpty ? "正在載入報告內容..." : _deepAnalysisText,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalAnalysisPanel() {
    double p = _safeNum('protein'),
        f = _safeNum('fat'),
        m = _safeNum('moisture'),
        fb = _safeNum('fiber');
    double rawAsh = _safeNum('ash'),
        ca = _safeNum('calcium'),
        ph = _safeNum('phosphorus');
    double ash = (rawAsh == 0) ? 9.0 : rawAsh;
    double carb = max(0, 100 - p - f - fb - m - ash);
    double dryFactor = (_isDMB && m < 100) ? 100 / (100 - m) : 1.0;

    double ratioVal = (ph > 0) ? (ca / ph) : 0.0;
    String ratioText = (ph > 0) ? "${ratioVal.toStringAsFixed(2)} : 1" : "N/A";
    Color ratioColor = (ratioVal >= 1.1 && ratioVal <= 1.4)
        ? Colors.green
        : Colors.orange;

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: SizedBox(
            height: 160,
            child: PieChart(
              PieChartData(
                sections: [
                  _pieSection(p * dryFactor, Colors.redAccent),
                  _pieSection(f * dryFactor, Colors.orangeAccent),
                  _pieSection(carb * dryFactor, Colors.blueAccent),
                  if (!_isDMB) _pieSection(m, Colors.lightBlue.shade200),
                  _pieSection(fb * dryFactor, Colors.green.shade300),
                  _pieSection(ash * dryFactor, Colors.grey.shade400),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Column(
            children: [
              _dataRow("蛋白質", p * dryFactor, Colors.redAccent),
              _dataRow("脂肪", f * dryFactor, Colors.orangeAccent),
              _dataRow("碳水(估)", carb * dryFactor, Colors.blueAccent),
              _dataRow("纖維", fb * dryFactor, Colors.green.shade300),
              _dataRow(
                rawAsh == 0 ? "灰分(未提供預設9%)" : "灰分",
                ash * dryFactor,
                Colors.grey.shade400,
              ),
              _dataRow("鈣磷比", 0, ratioColor, customVal: ratioText),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCPValueRow() {
    double pricePerGram = _calculatePricePerKg() / 1000.0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "1克單價：",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Text(
            "${pricePerGram.toStringAsFixed(3)} 元",
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthAlerts() {
    double p = _safeNum('protein'),
        f = _safeNum('fat'),
        fb = _safeNum('fiber'),
        m = _safeNum('moisture'),
        rawAsh = _safeNum('ash');
    double ash = (rawAsh == 0) ? 9.0 : rawAsh;
    double carbDMB = (m < 100)
        ? (100 - p - f - fb - m - ash) * (100 / (100 - m))
        : 0;
    double threshold = _isCat ? 25.0 : 50.0;

    if (carbDMB > threshold) {
      return Container(
        margin: const EdgeInsets.only(top: 15),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "⚠️ 提醒：此食品碳水比例(DMB)對${_isCat ? '貓' : '狗'}來說偏高 (${carbDMB.toStringAsFixed(1)}%)。",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildFeedingCalculator() {
    double p = _safeNum('protein'),
        f = _safeNum('fat'),
        m = _safeNum('moisture'),
        fb = _safeNum('fiber'),
        rawAsh = _safeNum('ash');
    double ash = (rawAsh == 0) ? 9.0 : rawAsh;
    double carb = max(0, 100 - p - f - fb - m - ash);
    double kcalPerKg = (p * 3.5 + f * 8.5 + carb * 3.5) * 10;

    // ✅ 關鍵修正：解決 num 賦值 double 報錯
    double rer = 70 * pow(_petWeight, 0.75).toDouble();
    double der = rer * _factor;
    double currentFoodGrams = kcalPerKg > 0
        ? ((der * _wetFoodRatio) / kcalPerKg) * 1000
        : 0;
    double dailyCost = currentFoodGrams * (_calculatePricePerKg() / 1000.0);

    return Column(
      children: [
        const Divider(),
        const Text(
          "⚖️ 伙食費與餵食估計",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Slider(
          value: _wetFoodRatio,
          min: 0,
          max: 1.0,
          divisions: 10,
          onChanged: (v) => setState(() => _wetFoodRatio = v),
        ),
        Text("此食品佔總熱量：${(_wetFoodRatio * 100).toInt()}%"),
        Slider(
          value: _petWeight,
          min: 1.0,
          max: 30.0,
          divisions: 290,
          onChanged: (v) => setState(() => _petWeight = v),
        ),
        Text("體重: ${_petWeight.toStringAsFixed(1)} kg"),
        DropdownButton<double>(
          value: _factor,
          isExpanded: true,
          items: (_isCat ? _catFactors : _dogFactors).entries
              .map((e) => DropdownMenuItem(value: e.value, child: Text(e.key)))
              .toList(),
          onChanged: (v) => setState(() => _factor = v!),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("建議餵食量"),
                  Text(
                    "${currentFoodGrams.toStringAsFixed(1)} 克",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("預估伙食費 (每日)"),
                  Text(
                    "${dailyCost.toStringAsFixed(1)} 元",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dataRow(String label, double val, Color color, {String? customVal}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
            const Spacer(),
            Text(
              customVal ?? "${val.toStringAsFixed(1)}%",
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );

  Widget _buildSecurityPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: TextField(
        decoration: const InputDecoration(
          labelText: 'Gemini API Key',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.vpn_key),
        ),
        obscureText: true,
        onChanged: (val) => _userApiKey = val,
      ),
    );
  }

  Widget _buildSpeciesToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _speciesBtn(
            "貓咪",
            Icons.pets,
            _isCat,
            () => setState(() {
              _isCat = true;
              _factor = 1.2;
            }),
          ),
          _speciesBtn(
            "狗狗",
            Icons.pets,
            !_isCat,
            () => setState(() {
              _isCat = false;
              _factor = 1.6;
            }),
          ),
        ],
      ),
    );
  }

  Widget _speciesBtn(
    String label,
    IconData icon,
    bool isActive,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        decoration: BoxDecoration(
          color: isActive ? Colors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? Colors.white : Colors.grey, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceWeightInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              decoration: const InputDecoration(
                labelText: '總價格',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (val) =>
                  setState(() => _totalPrice = double.tryParse(val) ?? 0.0),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextField(
              decoration: const InputDecoration(
                labelText: '重量',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (val) =>
                  setState(() => _inputWeight = double.tryParse(val) ?? 1.0),
            ),
          ),
          const SizedBox(width: 10),
          DropdownButton<String>(
            value: _weightUnit,
            items: [
              'kg',
              'lb',
              'g',
            ].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
            onChanged: (val) => setState(() => _weightUnit = val!),
          ),
        ],
      ),
    );
  }

  Widget _buildDMBToggle() {
    return SwitchListTile(
      title: const Text(
        "切換為乾物質比 (DMB)",
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      value: _isDMB,
      onChanged: (val) => setState(() => _isDMB = val),
    );
  }

  Widget _buildIngredientExpansion() {
    return Container(
      margin: const EdgeInsets.only(top: 15),
      child: ExpansionTile(
        title: const Text(
          "主要成分診斷",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        children: _topIngredients
            .map(
              (ing) => ListTile(
                leading: Icon(
                  ing['quality'] == 'good' ? Icons.check_circle : Icons.info,
                  color: ing['quality'] == 'good'
                      ? Colors.green
                      : Colors.orange,
                ),
                title: Text(
                  ing['name'] ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  ing['reason'] ?? '',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  PieChartSectionData _pieSection(double val, Color color) =>
      PieChartSectionData(
        color: color,
        value: val,
        radius: 40,
        showTitle: false,
      );
}
