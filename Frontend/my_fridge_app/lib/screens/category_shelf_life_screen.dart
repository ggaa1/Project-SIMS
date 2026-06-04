import 'package:flutter/material.dart';

import '../services/category_shelf_life_service.dart';
import '../services/ingredient_service.dart';
import '../theme/app_colors.dart';

/// 카테고리별 표준 유통기한(보관일수) 설정 화면.
/// 전역 기본값 위에 이 냉장고만의 override 를 두고, 식재료 추가 시
/// 자동 산정되는 유통기한의 기준을 조정한다. (expiry-spec-v1.md §5)
class CategoryShelfLifeScreen extends StatefulWidget {
  const CategoryShelfLifeScreen({super.key});

  @override
  State<CategoryShelfLifeScreen> createState() =>
      _CategoryShelfLifeScreenState();
}

class _CategoryShelfLifeScreenState extends State<CategoryShelfLifeScreen> {
  String? _fridgeId;
  List<CategoryShelfLife> _items = [];

  /// 저장 대기 변경분. 값 null = 기본값으로 복귀(override 제거).
  final Map<String, int?> _pending = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fridgeId = await IngredientService.currentFridgeId();
      final list = await CategoryShelfLifeService.getList(fridgeId);
      if (!mounted) return;
      setState(() {
        _fridgeId = fridgeId;
        _items = list;
        _pending.clear();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '유통기한 설정을 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _save() async {
    final fridgeId = _fridgeId;
    if (fridgeId == null || _pending.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final updated =
          await CategoryShelfLifeService.patch(fridgeId, Map.of(_pending));
      if (!mounted) return;
      setState(() {
        _items = updated;
        _pending.clear();
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장되었습니다. 다음에 추가하는 식재료부터 적용됩니다.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장에 실패했습니다. 값(1~3650) 또는 네트워크를 확인해주세요.')),
      );
    }
  }

  /// 행에 표시할 현재 값(저장 대기 반영). (days, 라벨, 변경대기 여부)
  ({int? days, String label, bool dirty}) _rowState(CategoryShelfLife item) {
    if (_pending.containsKey(item.category)) {
      final v = _pending[item.category];
      if (v == null) {
        return (days: null, label: '기본값으로 (저장 대기)', dirty: true);
      }
      return (days: v, label: '$v일 (변경됨)', dirty: true);
    }
    return (
      days: item.days,
      label: '${item.days}일 · ${item.isCustom ? '맞춤' : '기본'}',
      dirty: false,
    );
  }

  Future<void> _editRow(CategoryShelfLife item) async {
    final current = _pending.containsKey(item.category)
        ? (_pending[item.category] ?? item.days)
        : item.days;
    final controller = TextEditingController(text: current.toString());

    // 결과: null=취소, (reset:true)=기본값 복귀, (reset:false, value:n)=값 지정
    final result = await showDialog<({bool reset, int? value})>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('${item.category} 보관일수'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  suffixText: '일',
                  helperText: '1 ~ 3650 사이',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, (reset: true, value: null)),
              child: const Text('기본값으로'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim());
                if (v == null || v < 1 || v > 3650) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('1~3650 사이의 숫자를 입력해주세요.')),
                  );
                  return;
                }
                Navigator.pop(ctx, (reset: false, value: v));
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    setState(() {
      if (result.reset) {
        // 이미 기본(override 아님)인데 reset 누르면 변경 없음 → pending에서 제거.
        if (!item.isCustom) {
          _pending.remove(item.category);
        } else {
          _pending[item.category] = null;
        }
      } else {
        if (result.value == item.days && !item.isCustom) {
          // 기본값과 동일하게 입력 → 변경 아님.
          _pending.remove(item.category);
        } else {
          _pending[item.category] = result.value;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('카테고리별 유통기한'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textMain,
        elevation: 0,
      ),
      body: _buildBody(),
      bottomNavigationBar: _pending.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: _saving ? Colors.grey : AppColors.mainGreen,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              '저장 (${_pending.length}건 변경)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.warningRed)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            '식재료를 추가할 때 카테고리별로 이 보관일수를 기준으로 유통기한이 자동 계산됩니다. '
            '설정 변경은 다음에 추가하는 식재료부터 적용됩니다.',
            style: TextStyle(color: AppColors.textSub, fontSize: 13),
          ),
        ),
        ..._items.map(_buildRow),
      ],
    );
  }

  Widget _buildRow(CategoryShelfLife item) {
    final state = _rowState(item);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: state.dirty
            ? Border.all(color: AppColors.mainGreen)
            : null,
      ),
      child: ListTile(
        title: Text(
          item.category,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(state.label),
        trailing: const Icon(Icons.edit, size: 18, color: AppColors.textSub),
        onTap: () => _editRow(item),
      ),
    );
  }
}
