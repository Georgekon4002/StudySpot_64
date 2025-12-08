import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("StudySpot"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          
          // Δείχνουμε διαθέσιμες θέσεις (dummy)
          const Text(
            "26 / 52 seats available",
            style: TextStyle(fontSize: 20),
          ),

          const SizedBox(height: 20),

          // Dummy grid που θα γίνει τα τραπεζάκια
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, // 3 γραμμές τραπεζιών
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: 12, 
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pushNamed(context, '/focus');
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Icon(Icons.person),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
