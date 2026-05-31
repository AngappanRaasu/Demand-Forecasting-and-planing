import 'package:flutter/material.dart';

class ForecastingPage extends StatefulWidget {
  const ForecastingPage({super.key});

  @override
  State<ForecastingPage> createState() => _ForecastingPageState();
}

class _ForecastingPageState extends State<ForecastingPage> {

  /// SAMPLE CATEGORY → ITEMS DATA
  final Map<String, List<String>> categoryData = {
    for (int i = 1; i <= 10; i++)
      "Category $i":
          List.generate(10, (j) => "Category $i Product ${j + 1}")
  };

  /// SELECTED STATES
  List<String> selectedCategories = [];
  List<String> selectedItems = [];

  List<String> visibleItems = [];

  /// CATEGORY SELECT LOGIC
  void toggleCategory(String category, bool selected) {
    setState(() {
      if (selected) {
        selectedCategories.add(category);
      } else {
        selectedCategories.remove(category);

        /// REMOVE ITS ITEMS ALSO
        selectedItems.removeWhere(
          (item) => categoryData[category]!.contains(item),
        );
      }

      /// UPDATE VISIBLE ITEMS
      visibleItems = selectedCategories
          .expand((cat) => categoryData[cat]!)
          .toList();
    });
  }

  /// ITEM SELECT LOGIC
  void toggleItem(String item) {
    setState(() {
      if (selectedItems.contains(item)) {
        selectedItems.remove(item);
      } else {
        selectedItems.add(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [

          /// LEFT CATEGORY PANEL
          Container(
            width: 260,
            color: Colors.grey.shade200,
            padding: const EdgeInsets.all(12),
            child: ListView(
              children: [

                /// SELECT ALL CATEGORIES
                CheckboxListTile(
                  title: const Text("Select All"),
                  value: selectedCategories.length == categoryData.length,
                  onChanged: (val) {
                    setState(() {
                      if (val!) {
                        selectedCategories = categoryData.keys.toList();
                        visibleItems = categoryData.values.expand((e) => e).toList();
                      } else {
                        selectedCategories.clear();
                        selectedItems.clear();
                        visibleItems.clear();
                      }
                    });
                  },
                ),

                /// CATEGORY LIST
                ...categoryData.keys.map((category) {
                  return CheckboxListTile(
                    title: Text(category),
                    value: selectedCategories.contains(category),
                    onChanged: (val) =>
                        toggleCategory(category, val!),
                  );
                }),
              ],
            ),
          ),

          /// RIGHT ITEMS PANEL
          Expanded(
            child: Column(
              children: [

                /// ITEM COUNT
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "${selectedItems.length} items selected",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                /// ITEMS GRID
                Expanded(
                  child: visibleItems.isEmpty
                      ? const Center(
                          child: Text(
                            "Select category to view items",
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                            childAspectRatio: 3,
                          ),
                          itemCount: visibleItems.length,
                          itemBuilder: (context, index) {
                            final item = visibleItems[index];
                            final selected =
                                selectedItems.contains(item);

                            return GestureDetector(
                              onTap: () => toggleItem(item),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Colors.red
                                      : Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey,
                                  ),
                                ),
                                child: Text(item),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
