import 'package:flutter/material.dart';

class CookingModePage extends StatefulWidget {
  final String title;
  final List<String> instructions;

  const CookingModePage({
    super.key,
    required this.title,
    required this.instructions,
  });

  @override
  State<CookingModePage> createState() => _CookingModePageState();
}

class _CookingModePageState extends State<CookingModePage> {
  int currentStep = 0;

  @override
  Widget build(BuildContext context) {
    final hasSteps = widget.instructions.isNotEmpty;
    final stepText =
        hasSteps ? widget.instructions[currentStep] : 'Aucune étape';
    final totalSteps = widget.instructions.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: hasSteps
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Étape ${currentStep + 1} / $totalSteps',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE9DDD0)),
                      ),
                      child: Center(
                        child: Text(
                          stepText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 30,
                            height: 1.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F1A17),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: currentStep > 0
                              ? () {
                                  setState(() {
                                    currentStep--;
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Précédent'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: currentStep < totalSteps - 1
                              ? () {
                                  setState(() {
                                    currentStep++;
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Suivant'),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : const Center(
                child: Text(
                  'Aucune étape disponible',
                  style: TextStyle(fontSize: 24),
                ),
              ),
      ),
    );
  }
}
