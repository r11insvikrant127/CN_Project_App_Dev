import 'package:flutter/material.dart';

class FoodMenuScreen extends StatefulWidget {
  @override
  _FoodMenuScreenState createState() => _FoodMenuScreenState();
}

class _FoodMenuScreenState extends State<FoodMenuScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedDay = DateTime.now().weekday - 1;

  final List<String> _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  final List<String> _mealTypes = ['Breakfast', 'Lunch', 'Snacks', 'Dinner'];

  // Professional menu with categorized icons
  final Map<String, Map<String, List<Map<String, dynamic>>>> _weeklyMenu = {
    'Monday': {
      'Breakfast': [
        {'name': 'Poha', 'type': 'main'},
        {'name': 'Aloo Paratha', 'type': 'main'},
        {'name': 'Tea / Coffee', 'type': 'beverage'},
        {'name': 'Milk', 'type': 'beverage'},
        {'name': 'Seasonal Fruits', 'type': 'fruit'},
      ],
      'Lunch': [
        {'name': 'Dal Tadka', 'type': 'curry'},
        {'name': 'Paneer Butter Masala', 'type': 'curry'},
        {'name': 'Jeera Rice', 'type': 'rice'},
        {'name': 'Roti / Chapati', 'type': 'bread'},
        {'name': 'Fresh Salad', 'type': 'salad'},
        {'name': 'Pickle & Chutney', 'type': 'condiment'},
      ],
      'Snacks': [
        {'name': 'Samosa', 'type': 'snack'},
        {'name': 'Masala Chai', 'type': 'beverage'},
        {'name': 'Biscuits', 'type': 'snack'},
      ],
      'Dinner': [
        {'name': 'Chole Bhature', 'type': 'main'},
        {'name': 'Steam Rice', 'type': 'rice'},
        {'name': 'Raita', 'type': 'side'},
        {'name': 'Green Salad', 'type': 'salad'},
        {'name': 'Kheer', 'type': 'dessert'},
      ],
    },
    'Tuesday': {
      'Breakfast': [
        {'name': 'Idli Sambhar', 'type': 'main'},
        {'name': 'Dosa', 'type': 'main'},
        {'name': 'Coconut Chutney', 'type': 'condiment'},
        {'name': 'Tea / Coffee', 'type': 'beverage'},
        {'name': 'Fresh Juice', 'type': 'beverage'},
      ],
      'Lunch': [
        {'name': 'Rajma Masala', 'type': 'curry'},
        {'name': 'Mix Vegetable', 'type': 'curry'},
        {'name': 'Steam Rice', 'type': 'rice'},
        {'name': 'Roti / Chapati', 'type': 'bread'},
        {'name': 'Salad', 'type': 'salad'},
        {'name': 'Curd', 'type': 'side'},
      ],
      'Snacks': [
        {'name': 'Vegetable Pakora', 'type': 'snack'},
        {'name': 'Masala Chai', 'type': 'beverage'},
        {'name': 'Cake', 'type': 'dessert'},
      ],
      'Dinner': [
        {'name': 'Chicken Curry', 'type': 'nonveg'},
        {'name': 'Egg Curry', 'type': 'nonveg'},
        {'name': 'Rice', 'type': 'rice'},
        {'name': 'Roti', 'type': 'bread'},
        {'name': 'Salad', 'type': 'salad'},
      ],
    },
    'Wednesday': {
      'Breakfast': [
        {'name': 'Upma', 'type': 'main'},
        {'name': 'Bread Butter', 'type': 'main'},
        {'name': 'Tea / Coffee', 'type': 'beverage'},
        {'name': 'Banana', 'type': 'fruit'},
      ],
      'Lunch': [
        {'name': 'Sambar Rice', 'type': 'rice'},
        {'name': 'Vegetable Curry', 'type': 'curry'},
        {'name': 'Roti', 'type': 'bread'},
        {'name': 'Salad', 'type': 'salad'},
      ],
      'Snacks': [
        {'name': 'Bread Pakora', 'type': 'snack'},
        {'name': 'Tea', 'type': 'beverage'},
      ],
      'Dinner': [
        {'name': 'Kadhi Chawal', 'type': 'rice'},
        {'name': 'Roti', 'type': 'bread'},
        {'name': 'Salad', 'type': 'salad'},
        {'name': 'Pickle', 'type': 'condiment'},
      ],
    },
    'Thursday': {
      'Breakfast': [
        {'name': 'Puri Bhaji', 'type': 'main'},
        {'name': 'Tea / Coffee', 'type': 'beverage'},
        {'name': 'Fruits', 'type': 'fruit'},
      ],
      'Lunch': [
        {'name': 'Chana Masala', 'type': 'curry'},
        {'name': 'Rice', 'type': 'rice'},
        {'name': 'Roti', 'type': 'bread'},
        {'name': 'Salad', 'type': 'salad'},
      ],
      'Snacks': [
        {'name': 'Cutlets', 'type': 'snack'},
        {'name': 'Juice', 'type': 'beverage'},
      ],
      'Dinner': [
        {'name': 'Fish Curry', 'type': 'nonveg'},
        {'name': 'Rice', 'type': 'rice'},
        {'name': 'Roti', 'type': 'bread'},
        {'name': 'Salad', 'type': 'salad'},
      ],
    },
    'Friday': {
      'Breakfast': [
        {'name': 'Sandwich', 'type': 'main'},
        {'name': 'Tea / Coffee', 'type': 'beverage'},
        {'name': 'Cereal', 'type': 'main'},
      ],
      'Lunch': [
        {'name': 'Rajma Chawal', 'type': 'rice'},
        {'name': 'Roti', 'type': 'bread'},
        {'name': 'Salad', 'type': 'salad'},
        {'name': 'Curd', 'type': 'side'},
      ],
      'Snacks': [
        {'name': 'French Fries', 'type': 'snack'},
        {'name': 'Cold Coffee', 'type': 'beverage'},
      ],
      'Dinner': [
        {'name': 'Paneer Tikka', 'type': 'main'},
        {'name': 'Naan', 'type': 'bread'},
        {'name': 'Salad', 'type': 'salad'},
        {'name': 'Raita', 'type': 'side'},
      ],
    },
    'Saturday': {
      'Breakfast': [
        {'name': 'Masala Dosa', 'type': 'main'},
        {'name': 'Tea / Coffee', 'type': 'beverage'},
        {'name': 'Chutney', 'type': 'condiment'},
      ],
      'Lunch': [
        {'name': 'Biryani', 'type': 'rice'},
        {'name': 'Raita', 'type': 'side'},
        {'name': 'Salad', 'type': 'salad'},
        {'name': 'Papad', 'type': 'side'},
      ],
      'Snacks': [
        {'name': 'Pizza', 'type': 'snack'},
        {'name': 'Cold Drink', 'type': 'beverage'},
      ],
      'Dinner': [
        {'name': 'Butter Chicken', 'type': 'nonveg'},
        {'name': 'Naan', 'type': 'bread'},
        {'name': 'Salad', 'type': 'salad'},
        {'name': 'Dessert', 'type': 'dessert'},
      ],
    },
    'Sunday': {
      'Breakfast': [
        {'name': 'Pancakes', 'type': 'main'},
        {'name': 'Tea / Coffee', 'type': 'beverage'},
        {'name': 'Fruit Bowl', 'type': 'fruit'},
        {'name': 'Syrup', 'type': 'condiment'},
      ],
      'Lunch': [
        {'name': 'Special Thali', 'type': 'main'},
        {'name': 'Rice', 'type': 'rice'},
        {'name': 'Roti', 'type': 'bread'},
        {'name': 'Dessert', 'type': 'dessert'},
        {'name': 'Salad', 'type': 'salad'},
      ],
      'Snacks': [
        {'name': 'Pasta', 'type': 'snack'},
        {'name': 'Garlic Bread', 'type': 'bread'},
        {'name': 'Soft Drink', 'type': 'beverage'},
      ],
      'Dinner': [
        {'name': 'Mutton Curry', 'type': 'nonveg'},
        {'name': 'Rice', 'type': 'rice'},
        {'name': 'Roti', 'type': 'bread'},
        {'name': 'Salad', 'type': 'salad'},
        {'name': 'Sweet', 'type': 'dessert'},
      ],
    },
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _mealTypes.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('🍽️ Weekly Food Menu'),
        backgroundColor: Colors.deepOrange[700],
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _mealTypes.map((meal) => Tab(
            child: Text(
              meal,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          )).toList(),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 3,
        ),
      ),
      body: Column(
        children: [
          // Day Selector
          Container(
            height: 70,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              itemBuilder: (context, index) {
                bool isToday = index == (DateTime.now().weekday - 1);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDay = index;
                    });
                  },
                  child: Container(
                    width: 70,
                    margin: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      color: _selectedDay == index 
                          ? Colors.deepOrange[500] 
                          : isToday
                              ? (isDark ? Colors.blue[900]!.withOpacity(0.3) : Colors.blue[50])
                              : (isDark ? Colors.grey[800]! : Colors.grey[50]),
                      borderRadius: BorderRadius.circular(12),
                      border: _selectedDay == index 
                          ? null 
                          : isToday
                              ? Border.all(color: Colors.blue[300]!)
                              : Border.all(color: Theme.of(context).dividerColor),
                      boxShadow: _selectedDay == index ? [
                        BoxShadow(
                          color: Colors.deepOrange.withOpacity(0.3),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        )
                      ] : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _days[index].substring(0, 3),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: _selectedDay == index 
                                ? Colors.white 
                                : isToday
                                    ? (isDark ? Colors.blue[100] : Colors.blue[800])
                                    : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        SizedBox(height: 4),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _selectedDay == index 
                                ? Colors.white.withOpacity(0.2)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _selectedDay == index 
                                    ? Colors.white 
                                    : isToday
                                        ? (isDark ? Colors.blue[100] : Colors.blue[800])
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Menu Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _mealTypes.map((mealType) {
                return _buildMealTab(mealType, isDark);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealTab(String mealType, bool isDark) {
    final dayMenu = _weeklyMenu[_days[_selectedDay]];
    
    if (dayMenu == null) {
      return _buildEmptyMenuState('No menu available for ${_days[_selectedDay]}', isDark);
    }
    
    final items = dayMenu[mealType];
    
    if (items == null || items.isEmpty) {
      return _buildEmptyMenuState('No $mealType menu for ${_days[_selectedDay]}', isDark);
    }

    return Container(
      color: isDark ? Colors.grey[900] : Colors.grey[50],
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '${_days[_selectedDay]} • $mealType',
                style: TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.bold, 
                  color: isDark ? Colors.deepOrange[100] : Colors.deepOrange[800],
                ),
              ),
            ),
          ),
          SizedBox(height: 8),
          // Menu Items
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(8),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildFoodItem(item, index, isDark);
              },
            ),
          ),
          // Timing Info
          Container(
            padding: EdgeInsets.all(16),
            margin: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time, color: Colors.deepOrange[700], size: 20),
                SizedBox(width: 12),
                Text(
                  _getMealTiming(mealType),
                  style: TextStyle(
                    fontWeight: FontWeight.w600, 
                    color: isDark ? Colors.deepOrange[100] : Colors.deepOrange[800],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodItem(Map<String, dynamic> item, int index, bool isDark) {
    Color backgroundColor = _getTypeBackgroundColor(item['type']);
    Color textColor = _getTypeTextColor(item['type']);
    IconData icon = _getFoodIcon(item['type']);
    
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: backgroundColor.withOpacity(0.3),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: textColor, size: 22),
        ),
        title: Text(
          item['name'],
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        trailing: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: backgroundColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: backgroundColor.withOpacity(0.3)),
          ),
          child: Text(
            _getTypeLabel(item['type']),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  IconData _getFoodIcon(String type) {
    switch (type) {
      case 'main': return Icons.restaurant;
      case 'curry': return Icons.soup_kitchen;
      case 'rice': return Icons.rice_bowl;
      case 'bread': return Icons.breakfast_dining;
      case 'nonveg': return Icons.set_meal;
      case 'snack': return Icons.bakery_dining;
      case 'beverage': return Icons.local_cafe;
      case 'fruit': return Icons.apple;
      case 'salad': return Icons.grass;
      case 'side': return Icons.kitchen;
      case 'dessert': return Icons.icecream;
      case 'condiment': return Icons.emoji_food_beverage;
      default: return Icons.restaurant_menu;
    }
  }

  Color _getTypeBackgroundColor(String type) {
    switch (type) {
      case 'main': return Colors.orange[500]!;
      case 'curry': return Colors.red[500]!;
      case 'rice': return Colors.amber[500]!;
      case 'bread': return Colors.brown[500]!;
      case 'nonveg': return Colors.deepOrange[500]!;
      case 'snack': return Colors.purple[500]!;
      case 'beverage': return Colors.blue[500]!;
      case 'fruit': return Colors.green[500]!;
      case 'salad': return Colors.lightGreen[500]!;
      case 'side': return Colors.teal[500]!;
      case 'dessert': return Colors.pink[500]!;
      case 'condiment': return Colors.deepPurple[500]!;
      default: return Colors.grey[500]!;
    }
  }

  Color _getTypeTextColor(String type) {
    return Colors.white;
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'main': return 'MAIN';
      case 'curry': return 'CURRY';
      case 'rice': return 'RICE';
      case 'bread': return 'BREAD';
      case 'nonveg': return 'NON-VEG';
      case 'snack': return 'SNACK';
      case 'beverage': return 'DRINK';
      case 'fruit': return 'FRUIT';
      case 'salad': return 'SALAD';
      case 'side': return 'SIDE';
      case 'dessert': return 'SWEET';
      case 'condiment': return 'CONDIMENT';
      default: return type.toUpperCase();
    }
  }

  Widget _buildEmptyMenuState(String message, bool isDark) {
    return Container(
      color: isDark ? Colors.grey[900] : Colors.grey[50],
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Center(
              child: Text(
                '${_days[_selectedDay]} • Menu',
                style: TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.bold, 
                  color: isDark ? Colors.deepOrange[100] : Colors.deepOrange[800],
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.restaurant_menu, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  SizedBox(height: 20),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Please check back later for updates',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getMealTiming(String mealType) {
    switch (mealType) {
      case 'Breakfast': return '🕢 7:30 AM - 9:30 AM';
      case 'Lunch': return '🕛 12:00 PM - 2:00 PM';
      case 'Snacks': return '🕟 4:30 PM - 6:00 PM';
      case 'Dinner': return '🕢 7:30 PM - 9:30 PM';
      default: return '';
    }
  }
}
