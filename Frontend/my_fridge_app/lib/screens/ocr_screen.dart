import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/ingredient.dart';
import '../models/ocr_result.dart';
import '../services/auth_service.dart';
import '../services/category_shelf_life_service.dart';
import '../services/ingredient_service.dart';
import '../services/ocr_service.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav.dart';

enum RegisterMode { none, receipt, image, manual }

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final _manualFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _countController = TextEditingController(text: '1');
  final _expireDateController = TextEditingController();
  
  // 기본 카테고리
  String _selectedCategory = IngredientCategory.vegetable; 
  
  RegisterMode mode = RegisterMode.none;
  bool hasScanned = false;
  bool isAnalyzing = false;
  bool showCompleteMessage = false;
  String? ocrError;
  XFile? pickedImage;
  List<OcrDraftItem> draftItems = [];

  // 수동 추가용: 카테고리 → effective 보관일수 (자동입력 기준). 비어있으면 자동입력 생략.
  Map<String, int> _categoryDays = {};

  // 카테고리 목록
  static const List<String> _categories = IngredientCategory.all;

  @override
  void dispose() {
    _nameController.dispose();
    _countController.dispose();
    _expireDateController.dispose();
    super.dispose();
  }

  Future<void> pickImage(RegisterMode selectedMode, ImageSource source) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: source);

    if (image == null) return;

    setState(() {
      mode = selectedMode;
      pickedImage = image;
      hasScanned = true;
      isAnalyzing = true;
      draftItems = [];
      ocrError = null;
      showCompleteMessage = false;
    });

    await analyzePickedImage(image.path);
  }

  Future<void> analyzePickedImage(String imagePath) async {
    try {
      final result = await OcrService.analyzeImage(imagePath);

      if (!mounted) return;

      setState(() {
        draftItems = result.items;
        isAnalyzing = false;
        ocrError = draftItems.isEmpty ? '인식된 식재료가 없습니다. 다시 선택해주세요.' : null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isAnalyzing = false;
        ocrError = '이미지 분석에 실패했습니다. 다시 시도해주세요.';
      });
    }
  }

  Future<void> pickManualImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    setState(() {
      pickedImage = image;
      showCompleteMessage = false;
    });
  }

  void showImageSourceSheet(RegisterMode selectedMode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                imageSourceTile(
                  icon: Icons.camera_alt,
                  title: '사진 촬영',
                  onTap: () {
                    Navigator.pop(context);
                    pickImage(selectedMode, ImageSource.camera);
                  },
                ),
                const SizedBox(height: 8),
                imageSourceTile(
                  icon: Icons.photo_library,
                  title: '앨범에서 선택',
                  onTap: () {
                    Navigator.pop(context);
                    pickImage(selectedMode, ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void resetCamera() {
    setState(() {
      mode = RegisterMode.none;
      pickedImage = null;
      hasScanned = false;
      isAnalyzing = false;
      draftItems = [];
      ocrError = null;
      showCompleteMessage = false;
    });
  }

  Future<void> openManualForm() async {
    setState(() {
      mode = RegisterMode.manual;
      pickedImage = null;
      hasScanned = false;
      isAnalyzing = false;
      draftItems = [];
      ocrError = null;
      showCompleteMessage = false;
    });

    // 카테고리별 기본 보관일수를 받아 선택 카테고리의 유통기한을 자동 입력.
    // 실패해도 수동 입력은 그대로 진행(사용자가 직접 날짜 선택).
    try {
      final fridgeId = await IngredientService.currentFridgeId();
      final map = await CategoryShelfLifeService.effectiveDaysMap(fridgeId);
      if (!mounted) return;
      setState(() => _categoryDays = map);
      _autofillExpireForCategory(_selectedCategory);
    } catch (_) {
      // 무시 — 자동입력만 생략
    }
  }

  /// 선택된 카테고리의 effective 보관일수로 유통기한 필드를 채운다(사용자 수정 가능).
  void _autofillExpireForCategory(String category) {
    final days = _categoryDays[category];
    if (days == null) return;
    final d = DateTime.now().add(Duration(days: days));
    _expireDateController.text = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String emojiForCategory(String category) {
    switch (category) {
      case IngredientCategory.vegetable: return '🥬';
      case IngredientCategory.fruit: return '🍎';
      case IngredientCategory.meat: return '🥩';
      case IngredientCategory.seafood: return '🐟';
      case IngredientCategory.dairy: return '🥛';
      case IngredientCategory.egg: return '🥚';
      case IngredientCategory.snack: return '🥫';
      default: return '🍽️';
    }
  }

  // 직접 등록
  Future<void> registerManualIngredient() async {
    if (!(_manualFormKey.currentState?.validate() ?? false)) return;

    final expireDateStr = _expireDateController.text.trim();
    final expireDate = DateTime.tryParse(expireDateStr) ?? DateTime.now();

    await IngredientService.addIngredient(
      name: _nameController.text.trim(),
      category: _selectedCategory,
      emoji: emojiForCategory(_selectedCategory),
      count: int.tryParse(_countController.text.trim()) ?? 1,
      expireDate: expireDate,
      imageLocalPath: pickedImage?.path,
      addedVia: IngredientSource.manual,
    );

    setState(() {
      showCompleteMessage = true;
      _nameController.clear();
      _countController.text = '1';
      _expireDateController.clear();
      _selectedCategory = IngredientCategory.vegetable;
      pickedImage = null;
    });

    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          showCompleteMessage = false;
          mode = RegisterMode.none;
        });
      }
    });
  }

  Future<void> registerIngredient() async {
    if (AuthService.currentUser == null) return;
    final itemsToSave = draftItems
        .where((item) => item.name.trim().isNotEmpty)
        .toList();

    if (itemsToSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('등록할 식재료가 없습니다.')),
      );
      return;
    }

    final String source = mode == RegisterMode.receipt 
        ? IngredientSource.receipt 
        : IngredientSource.image;

    for (final item in itemsToSave) {
      await IngredientService.addIngredient(
        name: item.name.trim(),
        category: item.category,
        emoji: emojiForCategory(item.category),
        count: item.count,
        expireDate: item.expireDate,
        imageLocalPath: pickedImage?.path,
        addedVia: source,
      );
    }

    setState(() {
      showCompleteMessage = true;
    });

    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          showCompleteMessage = false;
          mode = RegisterMode.none;
          pickedImage = null;
          hasScanned = false;
          draftItems = [];
          ocrError = null;
        });
      }
    });
  }

  String getTitle() {
    if (mode == RegisterMode.receipt) return '영수증 인식 결과';
    if (mode == RegisterMode.image) return '이미지 인식 결과';
    if (mode == RegisterMode.manual) return '직접 등록하기';
    return '식재료 등록';
  }

  String getGuideText() {
    if (mode == RegisterMode.receipt) {
      return 'OCR 서버에서 영수증 텍스트를 추출했습니다.';
    }
    if (mode == RegisterMode.image) {
      return 'Image Recognition 서버에서 식재료를 추측했습니다.';
    }
    if (mode == RegisterMode.manual) {
      return '식재료 정보를 입력해주세요';
    }
    return '등록 방식을 선택해주세요';
  }

  Widget getResultText() {
    if (isAnalyzing) {
      return const Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('이미지를 분석하고 있습니다.', style: TextStyle(color: AppColors.textSub)),
        ],
      );
    }

    if (ocrError != null) {
      return Text(
        ocrError!,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.warningRed),
      );
    }

    return Column(
      children: [
        const Text(
          '분석된 식재료',
          style: TextStyle(color: AppColors.textSub, fontSize: 13),
        ),
        const SizedBox(height: 10),
        ...draftItems.asMap().entries.map(
              (entry) => draftItemEditor(entry.key, entry.value),
            ),
      ],
    );
  }

  Widget draftItemEditor(int index, OcrDraftItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.name,
                  decoration: const InputDecoration(
                    labelText: '품목명',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) => item.name = value,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    draftItems.removeAt(index);
                  });
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: IngredientCategory.all.contains(item.category)
                      ? item.category
                      : IngredientCategory.other,
                  decoration: const InputDecoration(
                    labelText: '카테고리',
                    border: InputBorder.none,
                  ),
                  items: IngredientCategory.all
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      item.category = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: item.quantity.isEmpty ? '1' : item.quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '수량',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) => item.quantity = value,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => pickDraftItemDate(item),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  const Icon(Icons.event, size: 18, color: AppColors.textSub),
                  const SizedBox(width: 8),
                  const Text(
                    '유통기한',
                    style: TextStyle(
                      color: AppColors.textSub,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.expireDateString,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.textSub),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> pickDraftItemDate(OcrDraftItem item) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: item.expireDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      item.expireDate = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: const BottomNav(currentIndex: 0),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 20),
                Text(
                  getTitle(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  getGuideText(),
                  style: const TextStyle(color: Colors.white70),
                ),
                Expanded(
                  child: Center(
                    child: mode == RegisterMode.manual
                        ? manualRegisterView()
                        : hasScanned
                        ? scannedResultView()
                        : selectModeView(),
                  ),
                ),
                if (hasScanned)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        imageSourceButtons(),
                        const SizedBox(height: 12),
                        registerButton(),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
              ],
            ),
            if (showCompleteMessage)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: AppColors.mainGreen),
                      SizedBox(width: 10),
                      Text(
                        '등록 완료',
                        style: TextStyle(
                          color: AppColors.textMain,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget selectModeView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          modeButton(
            title: '영수증으로 등록하기',
            icon: Icons.receipt_long,
            onTap: () => showImageSourceSheet(RegisterMode.receipt),
          ),
          const SizedBox(height: 16),
          modeButton(
            title: '이미지로 등록하기',
            icon: Icons.camera_alt,
            onTap: () => showImageSourceSheet(RegisterMode.image),
          ),
          const SizedBox(height: 16),
          modeButton(
            title: '직접 등록하기',
            icon: Icons.edit_note,
            onTap: openManualForm,
          ),
        ],
      ),
    );
  }

  Widget imageSourceTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.mainGreen),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textMain,
          fontWeight: FontWeight.bold,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget modeButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.mainGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.mainGreen, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget scannedResultView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Container(
        width: 310,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: pickedImage == null
                  ? Container(
                      width: 220,
                      height: 220,
                      color: const Color(0xFFF1F1EF),
                      child: const Center(child: Icon(Icons.image, size: 80)),
                    )
                  : Image.file(
                      File(pickedImage!.path),
                      width: 220,
                      height: 220,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(height: 16),
            getResultText(),
            if (!isAnalyzing && draftItems.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    draftItems.add(
                      OcrDraftItem(
                        name: '',
                        category: IngredientCategory.other,
                        quantity: '1',
                      ),
                    );
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('항목 추가'),
              ),
          ],
        ),
      ),
    );
  }

  Widget manualRegisterView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Form(
          key: _manualFormKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              manualTextField(
                controller: _nameController,
                label: '식재료 이름',
                hintText: '예: 양파',
                icon: Icons.eco,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '식재료 이름을 입력해주세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              manualImagePicker(),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: inputDecoration(label: '분류', icon: Icons.category),
                items: _categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedCategory = value;
                  });
                  _autofillExpireForCategory(value);
                },
              ),
              const SizedBox(height: 14),
              manualTextField(
                controller: _countController,
                label: '개수',
                hintText: '예: 2',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
                validator: (value) {
                  final count = int.tryParse(value?.trim() ?? '');
                  if (count == null || count <= 0) {
                    return '1개 이상으로 입력해주세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              manualTextField(
                controller: _expireDateController,
                label: '유통기한',
                hintText: 'YYYY-MM-DD',
                icon: Icons.event,
                readOnly: true,
                onTap: selectExpireDate,
                validator: (value) {
                  if (DateTime.tryParse(value?.trim() ?? '') == null) {
                    return '유통기한을 선택해주세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              registerManualButton(),
              const SizedBox(height: 10),
              TextButton(
                onPressed: resetCamera,
                child: const Text(
                  '등록 방식 다시 선택',
                  style: TextStyle(color: AppColors.textSub),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> selectExpireDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (pickedDate == null) return;

    _expireDateController.text =
        '${pickedDate.year.toString().padLeft(4, '0')}-'
        '${pickedDate.month.toString().padLeft(2, '0')}-'
        '${pickedDate.day.toString().padLeft(2, '0')}';
  }

  InputDecoration inputDecoration({
    required String label,
    required IconData icon,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon, color: AppColors.mainGreen),
      filled: true,
      fillColor: const Color(0xFFF7F8F5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.mainGreen),
      ),
    );
  }

  Widget manualTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    bool readOnly = false,
    VoidCallback? onTap,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      validator: validator,
      decoration: inputDecoration(label: label, icon: icon, hintText: hintText),
    );
  }

  Widget manualImagePicker() {
    return GestureDetector(
      onTap: pickManualImage,
      child: Container(
        width: double.infinity,
        height: 130,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: pickedImage == null
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library, color: AppColors.mainGreen),
                  SizedBox(height: 8),
                  Text(
                    '앨범에서 사진 선택',
                    style: TextStyle(
                      color: AppColors.textMain,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '선택 사항',
                    style: TextStyle(color: AppColors.textSub, fontSize: 12),
                  ),
                ],
              )
            : Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      File(pickedImage!.path),
                      width: double.infinity,
                      height: 130,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          pickedImage = null;
                        });
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget imageSourceButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        imageSourceCircleButton(
          icon: Icons.camera_alt,
          onTap: () => pickImage(mode, ImageSource.camera),
        ),
        const SizedBox(width: 18),
        imageSourceCircleButton(
          icon: Icons.photo_library,
          onTap: () => pickImage(mode, ImageSource.gallery),
        ),
      ],
    );
  }

  Widget imageSourceCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        height: 68,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 32),
      ),
    );
  }

  Widget registerButton() {
    return GestureDetector(
      onTap: registerIngredient,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.mainGreen,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Text(
            '식재료 등록하기',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget registerManualButton() {
    return GestureDetector(
      onTap: registerManualIngredient,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.mainGreen,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Text(
            '직접 등록하기',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
