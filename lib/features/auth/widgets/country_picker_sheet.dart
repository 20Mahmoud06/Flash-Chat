import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/core/utils/country_codes.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Telegram-style country picker: a searchable bottom sheet listing every
/// country with its flag and dialing code. Searching by country name
/// ("egypt") or by dialing code ("20") filters the list live.
class CountryPickerSheet extends StatefulWidget {
  const CountryPickerSheet({super.key});

  /// Opens the picker and resolves with the selected country (or null).
  static Future<CountryCode?> show(BuildContext context) {
    return showModalBottomSheet<CountryCode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CountryPickerSheet(),
    );
  }

  @override
  State<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<CountryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CountryCode> get _results => CountryCodes.search(_query);

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: Column(
          children: [
            SizedBox(height: 12.h),
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: colors.surfaceDim,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
              child: CustomText(
                text: 'Select a Country',
                textColor: colors.textPrimary,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                onChanged: (value) => setState(() => _query = value),
                style: TextStyle(color: colors.textPrimary, fontSize: 16.sp),
                cursorColor: Colors.lightBlueAccent,
                decoration: InputDecoration(
                  hintText: 'Search country name or code',
                  hintStyle: TextStyle(color: colors.textWeak, fontSize: 16.sp),
                  prefixIcon: Icon(Icons.search, color: colors.textWeak),
                  filled: true,
                  fillColor: colors.inputFill,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(
                      color: isDark
                          ? Colors.lightBlueAccent
                          : Colors.lightBlue.shade300,
                      width: 1.5.w,
                    ),
                  ),
                ),
              ),
            ),
            Divider(color: colors.divider, height: 1),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: CustomText(
                        text: 'No country found',
                        textColor: colors.textWeak,
                        fontSize: 16.sp,
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.only(bottom: 16.h),
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => Divider(
                        color: colors.divider,
                        height: 1,
                        indent: 56.w,
                      ),
                      itemBuilder: (context, index) {
                        final country = _results[index];
                        return InkWell(
                          onTap: () => Navigator.pop(context, country),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16.w, vertical: 12.h),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 32.w,
                                  child: CustomText(
                                    text: country.flag,
                                    fontSize: 22.sp,
                                  ),
                                ),
                                SizedBox(width: 14.w),
                                Expanded(
                                  child: CustomText(
                                    text: country.name,
                                    textColor: colors.textPrimary,
                                    fontSize: 16.sp,
                                  ),
                                ),
                                CustomText(
                                  text: country.code,
                                  textColor: colors.textSecondary,
                                  fontSize: 16.sp,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
