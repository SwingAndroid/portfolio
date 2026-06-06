import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/transaction_entity.dart';
import '../bloc/crypto_detail/crypto_detail_cubit.dart';

class AddTransactionSheet extends StatefulWidget {
  final String cryptoId;
  final String cryptoSymbol;

  const AddTransactionSheet({
    super.key,
    required this.cryptoId,
    required this.cryptoSymbol,
  });

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  TransactionType _type = TransactionType.buy;
  final _quantityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // ── type metadata ──────────────────────────────────────────────────────────

  Color get _typeColor {
    switch (_type) {
      case TransactionType.buy:
        return AppTheme.profit;
      case TransactionType.sell:
        return AppTheme.loss;
      case TransactionType.transferIn:
        return const Color(0xFF3B82F6);
      case TransactionType.transferOut:
        return const Color(0xFFF97316);
    }
  }

  String get _typeLabel {
    switch (_type) {
      case TransactionType.buy:
        return 'Add Buy';
      case TransactionType.sell:
        return 'Add Sell';
      case TransactionType.transferIn:
        return 'Add Transfer In';
      case TransactionType.transferOut:
        return 'Add Transfer Out';
    }
  }

  bool get _isTransfer => _type.isTransfer;

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'Add Transaction',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.cryptoSymbol,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 24),

                // 2 × 2 type selector
                _buildTypeSelector(),
                const SizedBox(height: 20),

                // Quantity
                TextFormField(
                  controller: _quantityCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Quantity (${widget.cryptoSymbol})',
                    hintText: '0.00',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter quantity';
                    if (double.tryParse(v) == null || double.parse(v) <= 0) {
                      return 'Enter a valid quantity';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Price per coin — optional for transfers
                TextFormField(
                  controller: _priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _isTransfer
                        ? 'Cost basis per coin (optional)'
                        : 'Price per coin (USD)',
                    hintText: '0.00',
                    prefixText: '\$ ',
                    prefixStyle:
                        const TextStyle(color: AppTheme.textSecondary),
                    helperText: _isTransfer
                        ? 'Leave empty if unknown'
                        : null,
                    helperStyle:
                        const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                  ),
                  validator: (v) {
                    if (_isTransfer) {
                      // Allow empty or zero for transfers
                      if (v != null && v.isNotEmpty) {
                        if (double.tryParse(v) == null || double.parse(v) < 0) {
                          return 'Enter a valid amount';
                        }
                      }
                      return null;
                    }
                    if (v == null || v.isEmpty) return 'Enter price';
                    if (double.tryParse(v) == null || double.parse(v) < 0) {
                      return 'Enter a valid price';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Date picker
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            color: AppTheme.textSecondary, size: 18),
                        const SizedBox(width: 12),
                        Text(
                          '${_date.day}/${_date.month}/${_date.year}',
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 15),
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_drop_down,
                            color: AppTheme.textSecondary),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Total preview (only when price is set)
                if (_quantityCtrl.text.isNotEmpty &&
                    _priceCtrl.text.isNotEmpty &&
                    (double.tryParse(_priceCtrl.text) ?? 0) > 0)
                  _buildTotalPreview(),

                const SizedBox(height: 8),

                // Submit button
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _typeColor,
                    foregroundColor: _type == TransactionType.buy
                        ? Colors.black
                        : Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          _typeLabel,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 2 × 2 type selector ────────────────────────────────────────────────────

  Widget _buildTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Row(
            children: [
              _TypeChip(
                label: 'Buy',
                icon: Icons.arrow_downward_rounded,
                isSelected: _type == TransactionType.buy,
                color: AppTheme.profit,
                onTap: () => setState(() => _type = TransactionType.buy),
              ),
              _TypeChip(
                label: 'Sell',
                icon: Icons.arrow_upward_rounded,
                isSelected: _type == TransactionType.sell,
                color: AppTheme.loss,
                onTap: () => setState(() => _type = TransactionType.sell),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _TypeChip(
                label: 'Transfer In',
                icon: Icons.call_received_rounded,
                isSelected: _type == TransactionType.transferIn,
                color: const Color(0xFF3B82F6),
                onTap: () =>
                    setState(() => _type = TransactionType.transferIn),
              ),
              _TypeChip(
                label: 'Transfer Out',
                icon: Icons.call_made_rounded,
                isSelected: _type == TransactionType.transferOut,
                color: const Color(0xFFF97316),
                onTap: () =>
                    setState(() => _type = TransactionType.transferOut),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalPreview() {
    final qty = double.tryParse(_quantityCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final total = qty * price;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _isTransfer ? 'Cost basis total' : 'Total',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          Text(
            '\$${total.toStringAsFixed(2)}',
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2009),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primary,
            onPrimary: Colors.black,
            surface: AppTheme.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    // For transfers, price is optional — default to 0 if empty
    final priceText = _priceCtrl.text.trim();
    final pricePerCoin = priceText.isEmpty ? 0.0 : double.parse(priceText);

    final transaction = TransactionEntity(
      id: const Uuid().v4(),
      cryptoId: widget.cryptoId,
      type: _type,
      quantity: double.parse(_quantityCtrl.text),
      pricePerCoin: pricePerCoin,
      date: _date,
    );

    await context.read<CryptoDetailCubit>().addNewTransaction(transaction);

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.of(context).pop();
    }
  }
}

// ── Type chip widget ───────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: color, width: 1.5) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: isSelected ? color : AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : AppTheme.textSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
