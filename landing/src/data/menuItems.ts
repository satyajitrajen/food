export interface MenuItem {
  id: string;
  name: string;
  category: 'popular' | 'starters' | 'mains' | 'biryani' | 'beverages';
  price: number;
  isVeg: boolean;
  description: string;
}

export const MENU_ITEMS: MenuItem[] = [
  {
    id: 'item-1',
    name: 'Hyderabadi Chicken Dum Biryani',
    category: 'popular',
    price: 320,
    isVeg: false,
    description: 'Slow-cooked fragrant basmati rice layered with tender spiced chicken & saffron.',
  },
  {
    id: 'item-2',
    name: 'Paneer Butter Masala',
    category: 'popular',
    price: 260,
    isVeg: true,
    description: 'Fresh cottage cheese cubes simmered in a rich tomato, butter & cashew gravy.',
  },
  {
    id: 'item-3',
    name: 'Crispy Butter Masala Dosa',
    category: 'popular',
    price: 130,
    isVeg: true,
    description: 'Fermented golden crepe filled with spiced potato masala, served with 2 chutneys & sambar.',
  },
  {
    id: 'item-4',
    name: 'South Indian Filter Coffee',
    category: 'beverages',
    price: 60,
    isVeg: true,
    description: 'Traditional chicory-infused brass filter brew frothed with boiling whole milk.',
  },
  {
    id: 'item-5',
    name: 'Tandoori Chicken (Half)',
    category: 'starters',
    price: 280,
    isVeg: false,
    description: 'Charcoal-grilled chicken marinated in spiced yogurt and Kashmiri red chili.',
  },
  {
    id: 'item-6',
    name: 'Crispy Corn & Water Chestnut',
    category: 'starters',
    price: 220,
    isVeg: true,
    description: 'Wok-tossed sweet corn kernels with crushed pepper, scallions, and lemon butter.',
  },
  {
    id: 'item-7',
    name: 'Dal Makhani (Overnight Slow Cooked)',
    category: 'mains',
    price: 240,
    isVeg: true,
    description: 'Black lentils slow-cooked for 16 hours with churned butter and dairy cream.',
  },
  {
    id: 'item-8',
    name: 'Butter Naan',
    category: 'biryani',
    price: 55,
    isVeg: true,
    description: 'Leavened flatbread baked in traditional clay tandoor and brushed with salted butter.',
  },
  {
    id: 'item-9',
    name: 'Mango Lassi (Malai Topped)',
    category: 'beverages',
    price: 110,
    isVeg: true,
    description: 'Chilled thick yogurt churned with Alphonso mango pulp and cardamom.',
  },
];
