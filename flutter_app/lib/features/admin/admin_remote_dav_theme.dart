import 'package:flutter/material.dart';

/// Route-local implementation of the saved DAV prototype palette.
class AdminDavScaffold extends StatelessWidget {
  const AdminDavScaffold({
    super.key,
    this.appBar,
    this.body,
    this.backgroundColor = Colors.white,
  });
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    const blue = Color(0xff0b57ee), navy = Color(0xff0c192e);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xffcbd5e1)),
    );
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: base.colorScheme.copyWith(
          primary: blue,
          onPrimary: Colors.white,
          onSurface: navy,
          surface: Colors.white,
        ),
        textTheme: base.textTheme.apply(bodyColor: navy, displayColor: navy),
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: Colors.white,
          foregroundColor: navy,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: navy,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
            shape: WidgetStatePropertyAll(shape),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (base.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                shape: WidgetStatePropertyAll(shape),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.disabled)
                      ? navy.withValues(alpha: .38)
                      : blue,
                ),
                side: WidgetStateProperty.resolveWith(
                  (states) => BorderSide(
                    color: states.contains(WidgetState.disabled)
                        ? blue.withValues(alpha: .2)
                        : blue,
                  ),
                ),
              ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? navy.withValues(alpha: .38)
                  : blue,
            ),
          ),
        ),
        chipTheme: base.chipTheme.copyWith(
          selectedColor: const Color(0xffeaf2ff),
          backgroundColor: Colors.white,
          shape: shape,
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          fillColor: Colors.white,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: blue, width: 2),
          ),
        ),
        textSelectionTheme: base.textSelectionTheme.copyWith(
          cursorColor: blue,
          selectionColor: blue.withValues(alpha: .2),
          selectionHandleColor: blue,
        ),
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: appBar,
        body: body,
      ),
    );
  }
}
