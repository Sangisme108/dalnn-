import '../models/inventory_item.dart';
import '../models/product.dart';

class ProductAssetResolver {
  static const String defaultProductAsset = 'assets/images/default_product.png';

  static const Map<String, String> _assetBySku = {
    'prod001': 'assets/images/chuoi.png',
    'prod002': 'assets/images/dautay.jpg',
    'prod003': 'assets/images/tao.png',
    'prod004': 'assets/images/dua.jpg',
    'prod005': 'assets/images/duahau.jpg',
    'prod006': 'assets/images/xotthaixatac.jpg',
    'prod007': 'assets/images/XotBBQ.png',
    'prod008': 'assets/images/muoiotchanh.png',
    'prod009': 'assets/images/xotkimquat.jpg',
    'prod010': 'assets/images/sottrungmuoi.png',
    'prod011': 'assets/images/trathtruetea.jpg',
    'prod012': 'assets/images/tradaohatchia.jpg',
    'prod013': 'assets/images/C2.jpg',
    'prod014': 'assets/images/trahoanhai.png',
    'prod015': 'assets/images/trachanhmatong.jpg',
    '893000000006': 'assets/products/lavie.jpg',
  };

  static String forProduct(Product product) {
    return resolve(
      id: product.id,
      barcode: product.barcode,
      name: product.name,
      imageUrl: product.imageUrl,
    );
  }

  static String forInventoryItem(InventoryItem item) {
    return resolve(
      id: item.id,
      barcode: item.id,
      name: item.name,
      imageUrl: item.imageUrl,
    );
  }

  static String forMap(Map<String, dynamic> product) {
    return resolve(
      id: (product['product_id'] ?? product['id'])?.toString(),
      barcode: product['barcode']?.toString(),
      name: (product['product_name'] ?? product['name'])?.toString(),
      imageUrl: (product['image_url'] ?? product['imageUrl'])?.toString(),
    );
  }

  static String resolve({
    String? id,
    String? barcode,
    String? name,
    String? imageUrl,
  }) {
    final trimmedImageUrl = (imageUrl ?? '').trim();
    if (trimmedImageUrl.startsWith('assets/')) {
      return trimmedImageUrl;
    }

    final normalizedId = _normalize(id);
    final normalizedBarcode = _normalize(barcode);
    final normalizedName = _normalize(name);
    final normalizedImageUrl = _normalize(trimmedImageUrl);

    for (final key in [normalizedBarcode, normalizedId]) {
      if (key.isNotEmpty && _assetBySku.containsKey(key)) {
        return _assetBySku[key]!;
      }
    }

    final searchable = '$normalizedName $normalizedImageUrl';

    if (_containsAny(searchable, const ['chaochongdinh', 'chaocdongdinh'])) {
      return 'assets/products/chao_chong_dinh.jpg';
    }
    if (_containsAny(searchable, const ['iphone17promax', 'iphone17pro'])) {
      return 'assets/products/iphone_17_pro_max.jpg';
    }
    if (_containsAny(searchable, const ['nuoccam', 'orangejuice'])) {
      return 'assets/products/nuoc_cam.jpg';
    }
    if (_containsAny(searchable, const [
      'nuocloclavie',
      'nuocsuoilavie',
      'lavie',
      'nuocloc',
    ])) {
      return 'assets/products/lavie.jpg';
    }
    if (_containsAny(searchable, const ['biasaigon', 'saigonbeer'])) {
      return 'assets/images/biasaigon.jpg';
    }
    if (_containsAny(searchable, const ['c2', 'traxanhc2'])) {
      return 'assets/images/C2.jpg';
    }
    if (_containsAny(searchable, const ['dautay', 'strawberry'])) {
      return 'assets/images/dautay.jpg';
    }
    if (_containsAny(searchable, const ['duahau', 'watermelon'])) {
      return 'assets/images/duahau.jpg';
    }
    if (_containsAny(searchable, const ['dua', 'pineapple'])) {
      return 'assets/images/dua.jpg';
    }
    if (_containsAny(searchable, const ['muoiotchanh'])) {
      return 'assets/images/muoiotchanh.png';
    }
    if (_containsAny(searchable, const ['xotthaixatac'])) {
      return 'assets/images/xotthaixatac.jpg';
    }
    if (_containsAny(searchable, const ['xotbbq', 'bbq'])) {
      return 'assets/images/XotBBQ.png';
    }
    if (_containsAny(searchable, const ['xotkimquat'])) {
      return 'assets/images/xotkimquat.jpg';
    }
    if (_containsAny(searchable, const ['sottrungmuoi', 'xottrungmuoi'])) {
      return 'assets/images/sottrungmuoi.png';
    }
    if (_containsAny(searchable, const ['trathtruetea', 'truetea'])) {
      return 'assets/images/trathtruetea.jpg';
    }
    if (_containsAny(searchable, const ['tradaohatchia'])) {
      return 'assets/images/tradaohatchia.jpg';
    }
    if (_containsAny(searchable, const ['trahoanhai'])) {
      return 'assets/images/trahoanhai.png';
    }
    if (_containsAny(searchable, const ['trachanhmatong', 'lipton'])) {
      return 'assets/images/trachanhmatong.jpg';
    }
    if (_containsAny(searchable, const ['suatuoi', 'vinamilk', 'milk'])) {
      return 'assets/images/suatuoi.jpg';
    }
    if (_containsAny(searchable, const ['chuoi', 'banana'])) {
      return 'assets/images/chuoi.png';
    }
    if (_containsAny(searchable, const ['tao', 'apple'])) {
      return 'assets/images/tao.png';
    }
    if (_containsAny(searchable, const ['dietcoke', 'diet'])) {
      return 'assets/images/dietcoca.png';
    }
    if (_containsAny(searchable, const ['coca', 'coke'])) {
      return 'assets/images/nuoccoca.png';
    }
    if (_containsAny(searchable, const ['cachua', 'tomato'])) {
      return 'assets/images/cachua.png';
    }
    if (_containsAny(searchable, const ['bongcai', 'broccoli'])) {
      return 'assets/images/bongcai.png';
    }

    return defaultProductAsset;
  }

  static bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  static String _normalize(String? value) {
    return _stripVietnameseAccents((value ?? '').toLowerCase())
        .replaceAll(RegExp(r'[\s_\-().]+'), '')
        .replaceAll('Ä‘', 'd')
        .replaceAll('Ã¡', 'a')
        .replaceAll('Ã ', 'a')
        .replaceAll('áº£', 'a')
        .replaceAll('Ã£', 'a')
        .replaceAll('áº¡', 'a')
        .replaceAll('Äƒ', 'a')
        .replaceAll('áº¯', 'a')
        .replaceAll('áº±', 'a')
        .replaceAll('áº³', 'a')
        .replaceAll('áºµ', 'a')
        .replaceAll('áº·', 'a')
        .replaceAll('Ã¢', 'a')
        .replaceAll('áº¥', 'a')
        .replaceAll('áº§', 'a')
        .replaceAll('áº©', 'a')
        .replaceAll('áº«', 'a')
        .replaceAll('áº­', 'a')
        .replaceAll('Ã©', 'e')
        .replaceAll('Ã¨', 'e')
        .replaceAll('áº»', 'e')
        .replaceAll('áº½', 'e')
        .replaceAll('áº¹', 'e')
        .replaceAll('Ãª', 'e')
        .replaceAll('áº¿', 'e')
        .replaceAll('á»', 'e')
        .replaceAll('á»ƒ', 'e')
        .replaceAll('á»…', 'e')
        .replaceAll('á»‡', 'e')
        .replaceAll('Ã­', 'i')
        .replaceAll('Ã¬', 'i')
        .replaceAll('á»‰', 'i')
        .replaceAll('Ä©', 'i')
        .replaceAll('á»‹', 'i')
        .replaceAll('Ã³', 'o')
        .replaceAll('Ã²', 'o')
        .replaceAll('á»', 'o')
        .replaceAll('Ãµ', 'o')
        .replaceAll('á»', 'o')
        .replaceAll('Ã´', 'o')
        .replaceAll('á»‘', 'o')
        .replaceAll('á»“', 'o')
        .replaceAll('á»•', 'o')
        .replaceAll('á»—', 'o')
        .replaceAll('á»™', 'o')
        .replaceAll('Æ¡', 'o')
        .replaceAll('á»›', 'o')
        .replaceAll('á»', 'o')
        .replaceAll('á»Ÿ', 'o')
        .replaceAll('á»¡', 'o')
        .replaceAll('á»£', 'o')
        .replaceAll('Ãº', 'u')
        .replaceAll('Ã¹', 'u')
        .replaceAll('á»§', 'u')
        .replaceAll('Å©', 'u')
        .replaceAll('á»¥', 'u')
        .replaceAll('Æ°', 'u')
        .replaceAll('á»©', 'u')
        .replaceAll('á»«', 'u')
        .replaceAll('á»­', 'u')
        .replaceAll('á»¯', 'u')
        .replaceAll('á»±', 'u')
        .replaceAll('Ã½', 'y')
        .replaceAll('á»³', 'y')
        .replaceAll('á»·', 'y')
        .replaceAll('á»¹', 'y')
        .replaceAll('á»µ', 'y');
  }

  static String _stripVietnameseAccents(String value) {
    const replacements = {
      'đ': 'd',
      'á': 'a',
      'à': 'a',
      'ả': 'a',
      'ã': 'a',
      'ạ': 'a',
      'ă': 'a',
      'ắ': 'a',
      'ằ': 'a',
      'ẳ': 'a',
      'ẵ': 'a',
      'ặ': 'a',
      'â': 'a',
      'ấ': 'a',
      'ầ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'ậ': 'a',
      'é': 'e',
      'è': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ẹ': 'e',
      'ê': 'e',
      'ế': 'e',
      'ề': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ệ': 'e',
      'í': 'i',
      'ì': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ị': 'i',
      'ó': 'o',
      'ò': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ọ': 'o',
      'ô': 'o',
      'ố': 'o',
      'ồ': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ộ': 'o',
      'ơ': 'o',
      'ớ': 'o',
      'ờ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ợ': 'o',
      'ú': 'u',
      'ù': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ụ': 'u',
      'ư': 'u',
      'ứ': 'u',
      'ừ': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ự': 'u',
      'ý': 'y',
      'ỳ': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
      'ỵ': 'y',
    };

    var result = value;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}
