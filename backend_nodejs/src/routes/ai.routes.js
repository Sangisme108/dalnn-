const express = require('express');
const pool = require('../config/db');
const { requireAuth } = require('../middlewares/auth.middleware');
const { FAQ_INSTRUCTION } = require('../config/smartsales-faq');

const router = express.Router();

function geminiText(payload) {
  return payload?.candidates?.[0]?.content?.parts
    ?.map((part) => part.text || '')
    .join('')
    .trim();
}

function geminiFunctionCall(payload) {
  return payload?.candidates?.[0]?.content?.parts
    ?.map((part) => part.functionCall)
    .find(Boolean) || null;
}

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

function sendAiFailure(res, error, fallback) {
  if (error.status === 429) {
    return res.status(503).json({ success: false, message: 'Trợ lý tư vấn đang hết hạn mức Gemini. Bạn vẫn có thể thêm giỏ và đặt hàng; phần tư vấn AI cần chờ hạn mức khôi phục.' });
  }
  return res.status(500).json({ success: false, message: fallback });
}

// Quy tắc dùng chung cho mọi phản hồi của Gemini. Dữ liệu về hàng hóa/đơn
// luôn do backend cung cấp; AI chỉ chịu trách nhiệm diễn đạt tự nhiên.
const SYSTEM_INSTRUCTION = `Bạn là SmartSales Assistant - trợ lý đặt hàng online tận nhà cho ứng dụng bán hàng.

=== QUY TẮC TƯ VẤN VÀ XỬ LÝ NGỮ CẢNH BẮT BUỘC ===
- Ngân sách là yêu cầu tư vấn: đưa nhiều sản phẩm cụ thể với giá không vượt ngân sách và lý do phù hợp; không biến tiền thành số lượng.
- Cân/kí/ký là kg. Tuyệt đối không đổi kg thành hộp/chai/gói hoặc ngược lại nếu hệ thống không có dữ liệu quy đổi chính xác. Kiểm tra đơn vị bán trước khi gọi công cụ.
- Khi vừa hỏi xác nhận một hành động và khách nói đúng/ừ/ok/đồng ý, thực hiện hành động đúng một lần nếu ngữ cảnh chưa thay đổi. Không hỏi xác nhận lặp lại.
- Nếu khách hỏi điều khác hoặc đổi ý, ưu tiên ý định mới và bỏ xác nhận cũ.
- Nếu thiếu dữ liệu, chỉ hỏi một thông tin quan trọng nhất. Không tự tạo trạng thái giỏ hay kết quả thao tác. Công cụ thất bại phải nói chưa thực hiện được và đưa cách xử lý.

=== SMARTSALES ASSISTANT V3.0 — VAI TRÒ VÀ CÁCH PHỤC VỤ ===
Bạn là nhân viên tư vấn mua sắm chuyên nghiệp, không phải chatbot trả lời theo kịch bản. Mục tiêu là giúp khách mua sắm đúng và thuận tiện; sự hài lòng quan trọng hơn việc cố chốt đơn.

Trước mỗi phản hồi, hãy xác định ý định của tin nhắn mới nhất: chào hỏi, tìm sản phẩm, hỏi thông tin, tư vấn ngân sách, so sánh, thêm/xem/sửa giỏ, đặt hàng, tra cứu đơn, từ chối mua, hoặc trò chuyện thường. Hiểu tiếng Việt không dấu, viết tắt và lỗi chính tả theo toàn bộ câu: k/ko/không, sp, 100k, 1tr, ship, add giỏ. Ví dụ “tôi có 100k mua được gì” luôn là tư vấn ngân sách, KHÔNG phải số lượng 100 kg.

Quy tắc theo ý định:
- Tìm sản phẩm: nêu các hàng thực tế phù hợp, không tự thêm giỏ.
- Hỏi giá, mô tả, dung tích, khối lượng, tồn kho hoặc hạn dùng: trả lời đúng phần được hỏi; nếu dữ liệu chưa có thì nói chưa có dữ liệu, không chuyển thành lời mời mua.
- Tư vấn ngân sách: chọn khoảng 3–5 sản phẩm có giá bằng hoặc thấp hơn ngân sách từ DỮ LIỆU HỆ THỐNG; có thể gợi ý kết hợp nhưng không tự thêm hàng.
- So sánh: chỉ so sánh dựa trên dữ liệu thật và tiêu chí khách hỏi; không khẳng định sở thích chủ quan như một sự thật.
- Thêm giỏ: chỉ gọi addToCart khi sản phẩm, số lượng và ý định mua đã rõ. Nếu chưa rõ đơn vị hoặc sản phẩm, hỏi đúng một câu làm rõ. Chỉ thông báo thành công sau KẾT QUẢ CÔNG CỤ thành công.
- Xem/sửa giỏ, tạo/tra cứu đơn: chỉ dùng kết quả hệ thống thực tế; không tự giả định giỏ hay trạng thái đơn.
- Khách nói “không mua”, “thôi”, “để sau”, “chỉ hỏi”: dừng ý định mua đang chờ, không thêm giỏ/đặt đơn và không thúc giục.
- Câu hỏi ngoài mua sắm: trả lời ngắn gọn, tự nhiên; không cố ép khách quay về đặt hàng.

Ngữ cảnh chỉ dùng để hiểu sản phẩm đang được nói tới. Tin nhắn mới nhất quyết định hành động hiện tại; không lặp lại thao tác cũ và không coi mọi “ok/được” là xác nhận, trừ khi có đề nghị xác nhận rõ ràng ngay trước đó hoặc có ngữ cảnh XÁC NHẬN THÊM GIỎ an toàn từ hệ thống.

Nguyên tắc dữ liệu: tuyệt đối không tự tạo giá, khuyến mại, số lượng tồn kho, trạng thái đơn hàng, thành phần hay công dụng sản phẩm. Chỉ nêu những dữ liệu được đặt trong phần DỮ LIỆU HỆ THỐNG hoặc KẾT QUẢ TRA CỨU. Trả lời bằng tiếng Việt lịch sự, thân thiện, ngắn gọn và dùng emoji vừa phải.

Bạn được phép trả lời kiến thức ẩm thực hoặc mua sắm mang tính chung (ví dụ món nào hợp để chấm với trái cây), nhưng phải nói rõ đó là gợi ý chung. Chỉ khi một mặt hàng xuất hiện trong DỮ LIỆU HỆ THỐNG mới được nói shop đang có bán mặt hàng đó; không tự gắn giá, tồn kho hay khuyến mại cho gợi ý chung.

=== QUY TẮC XỬ LÝ KHI KHÔNG CÓ THÔNG TIN HOẶC NGOÀI PHẠM VI ===
1. Khi không tìm thấy dữ liệu (sản phẩm, đơn hàng):
   - Không dùng một câu lặp đi lặp lại. Hãy linh hoạt diễn đạt theo nhiều cách tự nhiên.
   - Thừa nhận nhẹ nhàng và chủ động đề xuất giải pháp: hỏi thêm chi tiết, gợi ý danh mục có trong dữ liệu, hoặc đề nghị xem sản phẩm đang có.
2. Khi khách hỏi không liên quan đến bán hàng/giao hàng (thời tiết, toán học, tán gẫu):
   - Trả lời ngắn gọn, vui vẻ; sau đó khéo léo hướng lại việc tìm hoặc đặt sản phẩm.
3. Tự do câu từ: thay đổi cách chào, xưng hô và cấu trúc câu giữa các lượt để tự nhiên, nhưng không bịa dữ liệu.

=== QUY TẮC PHÂN BIỆT Ý ĐỊNH VÀ TƯ VẤN SẢN PHẨM ===
1. Khi khách hỏi tư vấn kết hợp/gợi ý (ví dụ: "Táo ăn với sốt gì ngon?", "Món này hợp với gì?"):
   - Hãy trả lời tư vấn ngắn gọn, thân thiện theo kiến thức chung trước.
   - Sau đó ưu tiên KẾT QUẢ TRA CỨU SẢN PHẨM PHỤ TRỢ. Nếu kết quả là NO_PRODUCTS_FOUND, nói tự nhiên rằng shop hiện chưa có bán món phụ trợ đó; không chuyển nhầm sang liệt kê món chính.
   - Chỉ mời khách đặt món chính nếu thông tin món chính xuất hiện trong dữ liệu.
2. Chỉ coi một câu là tìm/mua sản phẩm khi khách thật sự muốn xem giá, tồn kho, tìm tên hàng hoặc đặt mua. Không vì một từ như "táo" mà trả lời bằng danh sách hàng nếu ngữ cảnh là tư vấn.
3. Không được lặp mẫu "Dạ shop tìm thấy... Bạn muốn lấy số lượng bao nhiêu". Hãy tự viết câu trả lời dựa trên ý định và dữ liệu thực tế.

=== QUẢN LÝ NGỮ CẢNH VÀ HÀNH ĐỘNG ===
1. Ưu tiên ý định của tin nhắn mới nhất; dùng lịch sử chỉ để hiểu sản phẩm đang được nhắc đến.
2. Nếu khách hỏi giá, dung tích/khối lượng, mô tả, hạn dùng, thành phần, công dụng hoặc so sánh: trả lời thẳng thông tin đang có. Không biến câu hỏi này thành yêu cầu mua hay xác nhận đơn.
3. Nếu thiếu dữ liệu cụ thể, nói rõ chưa có thông tin chính xác. Không bịa khối lượng, dung tích, hạn dùng, phí ship, mã giảm giá, thời gian giao hay trạng thái đơn.
4. Chỉ thêm giỏ khi khách yêu cầu rõ hoặc đã đồng ý rõ; chỉ tạo đơn khi giỏ, địa chỉ, điện thoại, thanh toán và xác nhận cuối cùng đã đủ. Không lặp yêu cầu xác nhận cho cùng một nội dung.
5. Nếu khách đổi chủ đề khi đang mua, trả lời câu hỏi mới trước. Nếu khách nói thôi/không mua, tôn trọng ý định đó và không thúc giục.
6. Khi có dữ liệu của nhiều sản phẩm, có thể so sánh ưu/nhược điểm dựa hoàn toàn trên dữ liệu, rồi đề xuất phù hợp với tiêu chí khách hỏi. Nếu tiêu chí chưa đủ quan trọng để trả lời chính xác, chỉ hỏi một câu làm rõ.
7. Luôn trả lời trực tiếp trước; chỉ gợi ý bước tiếp theo khi thật sự hữu ích. Thông thường dùng 1–4 câu, không nói về công cụ hay quy trình nội bộ.

=== QUY TẮC BẮT BUỘC KHI THÊM VÀO GIỎ HÀNG (ADD TO CART) ===
1. Tuyệt đối không gọi addToCart khi khách hỏi ngân sách, giá, thông tin, khối lượng/trọng lượng, tư vấn, đang từ chối hoặc nói không mua.
2. Chỉ gọi addToCart khi khách nêu rõ ý định thêm/mua một sản phẩm cụ thể; sản phẩm và số lượng phải xác định được từ dữ liệu hoặc ngữ cảnh an toàn. Nếu một sản phẩm chỉ được xác định từ lời đề nghị ngay trước đó của trợ lý, lời đồng ý ngắn của khách cũng có thể là xác nhận.
3. Nếu không có dữ liệu khối lượng/trọng lượng, nói rõ thông số chưa được cập nhật; không thay bằng dung tích tiêu chuẩn hay dữ liệu tự suy đoán.
4. Trước khi gọi addToCart, kiểm tra tên/mã sản phẩm và số lượng trong DỮ LIỆU HỆ THỐNG. Không gọi công cụ chỉ vì một con số xuất hiện trong câu của khách.

=== VÍ DỤ ỨNG XỬ LINH HOẠT ===
- Không có sản phẩm: "Dạ hiện shop chưa thấy mặt hàng đó trong danh sách ạ. Bạn muốn thử danh mục khác hoặc mô tả thêm nhu cầu để mình tìm sát hơn không?"
- Không thấy đơn: "Mình vừa kiểm tra nhưng chưa thấy đơn này. Bạn xem lại mã đơn hoặc số điện thoại đặt hàng giúp mình nhé."
- Tán gẫu: "Haha, mình là AI nên mê nhất là hỗ trợ bạn mua sắm nhanh gọn nè 😊 Hôm nay bạn muốn tìm món gì để giao tận nhà?"

=== VÍ DỤ CÂU HỎI TƯ VẤN KẾT HỢP ===
- Khách: "Chấm táo với sốt nào của shop thì ngon ạ?"
- KẾT QUẢ TRA CỨU SẢN PHẨM PHỤ TRỢ: từ khóa "sốt" = NO_PRODUCTS_FOUND.
- Cách trả lời: "Táo thường hợp với sốt caramel, sữa chua hoặc muối ớt tùy khẩu vị ạ. Đây là gợi ý chung; hiện shop chưa có sản phẩm sốt trong danh mục. Bạn có muốn mình hỗ trợ xem táo đang có không?"

Nếu KẾT QUẢ TRA CỨU ghi NO_PRODUCTS_FOUND, NO_ORDERS_FOUND hoặc EMPTY_CART, hãy tạo một phản hồi khác nhau, tự nhiên dựa trên các danh mục được gợi ý. Nếu ghi OUT_OF_SCOPE, trả lời tán gẫu ngắn gọn. Không nói rằng đã gọi công cụ hay dùng từ kỹ thuật.

${FAQ_INSTRUCTION}`;

async function askGemini({ apiKey, userText, context = '', maxOutputTokens = 180 }) {
  const model = process.env.GEMINI_MODEL || 'gemini-3.8-flash';
  let response;
  let body;
  // Gemini đôi lúc báo quá tải; thử lại trước khi trả lỗi cho ứng dụng.
  for (let attempt = 0; attempt < 3; attempt += 1) {
    response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
          contents: [{ parts: [{ text: `${context}\n\nKHÁCH: ${userText}`.trim() }] }],
          generationConfig: { temperature: 0.5, topP: 0.9, maxOutputTokens },
        }),
      },
    );
    body = await response.json();
    if (response.ok || ![429, 503].includes(response.status) || attempt === 2) break;
    await delay(800 * (attempt + 1));
  }
  if (!response.ok) {
    const error = new Error(body?.error?.message || response.statusText || 'Gemini request failed');
    error.status = response.status;
    throw error;
  }
  const answer = geminiText(body);
  if (!answer) throw new Error('Gemini không trả về nội dung');
  return answer;
}

async function generateGeminiContent({ apiKey, contents, tools, toolConfig, maxOutputTokens = 260 }) {
  const model = process.env.GEMINI_MODEL || 'gemini-3.8-flash';
  let response;
  let body;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
          contents,
          ...(tools ? { tools } : {}),
          ...(toolConfig ? { toolConfig } : {}),
          generationConfig: { temperature: 0.5, topP: 0.9, maxOutputTokens },
        }),
      },
    );
    body = await response.json();
    if (response.ok || ![429, 503].includes(response.status) || attempt === 2) break;
    await delay(800 * (attempt + 1));
  }
  if (!response.ok) {
    const error = new Error(body?.error?.message || response.statusText || 'Gemini request failed');
    error.status = response.status;
    throw error;
  }
  return body;
}

const CART_TOOL = [{
  functionDeclarations: [{
    name: 'addToCart',
    description: 'Chỉ thêm sản phẩm vào giỏ khi khách yêu cầu mua/thêm cụ thể hoặc xác nhận rõ đề nghị thêm hàng ngay trước đó. Không gọi để trả lời tư vấn, ngân sách, giá, khối lượng hay khi khách từ chối.',
    parameters: {
      type: 'OBJECT',
      properties: {
        productId: { type: 'INTEGER', description: 'Mã product_id có trong dữ liệu hệ thống.' },
        quantity: { type: 'INTEGER', description: 'Số lượng nguyên dương khách muốn thêm.' },
      },
      required: ['productId', 'quantity'],
    },
  }],
}];

function hasExplicitCartIntent(message) {
  const text = normalizeSearchText(message);
  if (/\b(k|ko|khong|thoi|huy|khong mua|khong lay)\b/.test(text)) return false;
  if (/ngan sach|duoi\s*\d|gia\s*\d|mua.*(gi|duoc)|bao nhieu|khoi luong|trong luong|dung tich|thong tin|tu van/.test(text)) return false;
  return /(them.*(gio|cart)|bo.*(gio|cart)|mua|lay|dat)/.test(text);
}

function isConfirmation(message) {
  const text = normalizeSearchText(message).trim().replace(/[.!?,]/g, '')
    .replace(/^da\s+/, '').replace(/\s+(a|nha|nhe)$/, '').trim();
  if (/^(ok|oke|okay|dung|dung roi|u|uh|dong y|duoc|duoc roi|xac nhan|vang|yes|dc|roi|chot|chot don)$/.test(text)) return true;
  const fillers = new Set(['a', 'nha', 'nhe', 'em', 'anh', 'chi', 'shop', 'minh']);
  const affirmative = new Set(['xac', 'nhan', 'dong', 'y', 'dung', 'ok', 'oke', 'okay', 'duoc', 'dc', 'roi', 'vang', 'u', 'uh', 'yes', 'chot']);
  const words = text.split(/\s+/).filter((word) => !fillers.has(word));
  return words.length > 0 && words.every((word) => affirmative.has(word));
}

function canonicalUnit(unit) {
  const text = normalizeSearchText(unit).trim();
  if (['kg', 'kilogram', 'can', 'ki', 'ky'].includes(text)) return 'kg';
  return text;
}

function sanitizeHistory(history) {
  if (!Array.isArray(history)) return [];
  return history.slice(-8).map((entry) => {
    let text = String(entry?.text || '').trim().slice(0, 450);
    // Không chuyển thông tin giao nhận nhạy cảm sang mô hình AI.
    if (/(so nha|duong|phuong|quan|tinh|thanh pho|dia chi|sdt|so dien thoai|phone)/i.test(normalizeSearchText(text))) {
      text = '[Thông tin giao nhận đã được ẩn]';
    }
    text = text
      .replace(/(?:\+84|0)\d{9,10}\b/g, '[SĐT]')
      .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[email]');
    return { role: entry?.role === 'model' ? 'model' : 'user', text };
  }).filter((entry) => entry.text);
}

async function addProductToCart({ userId, productId, quantity, mode = 'add' }) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [products] = await connection.execute(
      `SELECT product_id, product_name, stock, status, unit
       FROM products WHERE product_id = ? FOR UPDATE`,
      [productId],
    );
    const product = products[0];
    if (!product || product.status !== 'active') throw new Error('Sản phẩm không còn bán');
    if (!Number.isInteger(quantity) || quantity <= 0) throw new Error('Số lượng không hợp lệ');
    if (Number(product.stock) < quantity) throw new Error(`Sản phẩm hiện chỉ còn ${product.stock} hàng`);

    const [carts] = await connection.execute(
      'SELECT cart_id FROM carts WHERE user_id = ? ORDER BY cart_id DESC LIMIT 1',
      [userId],
    );
    let cartId = carts[0]?.cart_id;
    if (!cartId) {
      const [created] = await connection.execute('INSERT INTO carts (user_id) VALUES (?)', [userId]);
      cartId = created.insertId;
    }
    const [existing] = await connection.execute(
      'SELECT quantity FROM cart_items WHERE cart_id = ? AND product_id = ? FOR UPDATE',
      [cartId, productId],
    );
    const cartQuantity = mode === 'set' ? quantity : Number(existing[0]?.quantity || 0) + quantity;
    if (cartQuantity > Number(product.stock)) {
      throw new Error(`Tổng số lượng trong giỏ vượt tồn kho ${product.stock} ${product.unit || 'món'}`);
    }
    await connection.execute(
      `INSERT INTO cart_items (cart_id, product_id, quantity)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE quantity = ${mode === 'set' ? 'VALUES(quantity)' : 'quantity + VALUES(quantity)'}`,
      [cartId, productId, quantity],
    );
    await connection.commit();
    return { success: true, productName: product.product_name, quantity, unit: product.unit, mode, cartQuantity };
  } catch (error) {
    await connection.rollback();
    return { success: false, message: error.message || 'Không thể thêm vào giỏ hàng' };
  } finally {
    connection.release();
  }
}

function normalizeSearchText(value) {
  return String(value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/đ/g, 'd');
}

// Từ khóa phụ trợ cần tra trước khi khách đang hỏi cách kết hợp/chế biến.
// Đây là dữ liệu tìm từ danh mục CSDL, không phải Gemini tự suy đoán shop có bán.
function companionTermsForAdvice(message) {
  const text = normalizeSearchText(message);
  const terms = [];
  if (/sot|sauce/.test(text)) terms.push('sốt');
  if (/nuoc cham/.test(text)) terms.push('nước chấm');
  if (/gia vi/.test(text)) terms.push('gia vị');
  return terms;
}

function companionSearchResult(products, message) {
  const terms = companionTermsForAdvice(message);
  if (terms.length === 0) return [];
  return terms.map((term) => {
    const normalizedTerm = normalizeSearchText(term);
    const matches = products.filter((product) => {
      const searchable = normalizeSearchText(
        `${product.product_name || ''} ${product.description || ''} ${product.category_name || ''}`,
      );
      return searchable.includes(normalizedTerm);
    });
    return {
      keyword: term,
      result: matches.length ? 'PRODUCTS_FOUND' : 'NO_PRODUCTS_FOUND',
      products: matches.map((product) => ({
        name: product.product_name,
        price: Number(product.price),
        unit: product.unit,
        stock: Number(product.stock),
      })),
    };
  });
}

router.post('/chat', requireAuth, async (req, res) => {
  const message = String(req.body?.message || '').trim();
  const apiKey = process.env.GEMINI_API_KEY;
  const userId = Number(req.user?.id || req.user?.user_id);
  const candidateProductIds = Array.isArray(req.body?.candidateProductIds)
    ? req.body.candidateProductIds.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0)
    : [];
  const requestedConfirmation = req.body?.confirmedCart;
  if (!message) return res.status(400).json({ success: false, message: 'Thiếu nội dung chat' });

  try {
    const [products] = await pool.execute(
      `SELECT p.product_id, p.product_name, p.description, p.price, p.unit, p.stock, c.category_name
       FROM products p
       LEFT JOIN categories c ON c.category_id = p.category_id
       WHERE p.status = 'active'
       ORDER BY p.product_name
       LIMIT 80`,
    );
    const catalog = products.map((product) => (
      `- ID ${product.product_id}: ${product.product_name} | ${product.category_name || 'Chưa phân loại'} | ${Number(product.price).toLocaleString('vi-VN')} VNĐ/${product.unit || 'món'} | tồn ${Number(product.stock)} | mô tả: ${String(product.description || 'Chưa có').slice(0, 160)}`
    )).join('\n');
    const candidates = candidateProductIds.length
      ? products.filter((product) => candidateProductIds.includes(Number(product.product_id)))
      : [];
    const confirmedProductId = Number(requestedConfirmation?.productId);
    const confirmedQuantity = Number(requestedConfirmation?.quantity);
    const confirmedMode = requestedConfirmation?.mode || 'add';
    if (!['add', 'set'].includes(confirmedMode)) return res.status(400).json({ success: false, message: 'Cách cập nhật giỏ không hợp lệ' });
    const confirmedProduct = candidates.find((product) => Number(product.product_id) === confirmedProductId);
    // Chỉ tin ngữ cảnh xác nhận do giao diện gửi khi sản phẩm nằm trong danh
    // sách đã hiển thị và số lượng là số nguyên dương. Đây vẫn chưa thêm hàng:
    // Gemini phải gọi addToCart, sau đó backend mới kiểm tra tồn và ghi CSDL.
    const confirmedCart = isConfirmation(message) && confirmedProduct && Number.isInteger(confirmedQuantity) && confirmedQuantity > 0
      ? { productId: confirmedProductId, quantity: confirmedQuantity, productName: confirmedProduct.product_name, unit: confirmedProduct.unit }
      : null;
    if (requestedConfirmation && !confirmedCart) {
      return res.status(400).json({ success: false, message: 'Yêu cầu xác nhận không hợp lệ. Bạn chọn lại sản phẩm và số lượng nhé.' });
    }
    if (confirmedCart) {
      // Quyết định mua đã được khách xác nhận. Thực thi công cụ CSDL trực
      // tiếp để quota/lỗi của dịch vụ tư vấn không chặn giao dịch đã rõ.
      const result = await addProductToCart({ userId, productId: confirmedCart.productId, quantity: confirmedCart.quantity, mode: confirmedMode });
      return res.json({ success: true, data: {
        answer: result.success
          ? (result.mode === 'set'
            ? `Giỏ hàng hiện có ${result.cartQuantity} ${result.unit || 'món'} ${result.productName}.`
            : `Đã thêm ${result.quantity} ${result.unit || 'món'} ${result.productName}. Tổng trong giỏ: ${result.cartQuantity} ${result.unit || 'món'}.`)
          : result.message,
        action: result.success ? { type: 'addToCart', productId: confirmedCart.productId, quantity: result.quantity } : null,
      } });
    }
    if (!apiKey) return res.status(503).json({ success: false, message: 'Chưa cấu hình GEMINI_API_KEY' });
    const candidateText = candidates.length
      ? candidates.map((product) => `- ID ${product.product_id}: ${product.product_name} | ${Number(product.price).toLocaleString('vi-VN')} VNĐ/${product.unit || 'món'} | tồn ${Number(product.stock)}`).join('\n')
      : '(Không có sản phẩm đang được chọn)';
    const companionText = JSON.stringify(companionSearchResult(products, message));
    const safeHistory = sanitizeHistory(req.body?.history);
    if (safeHistory.at(-1)?.role === 'user' && safeHistory.at(-1)?.text === message) safeHistory.pop();
    const confirmationText = confirmedCart
      ? `XÁC NHẬN THÊM GIỎ AN TOÀN: Khách vừa xác nhận thêm ${confirmedCart.quantity} ${confirmedCart.unit || 'món'} ${confirmedCart.productName}. Hãy gọi addToCart đúng productId ${confirmedCart.productId} và quantity ${confirmedCart.quantity} một lần.`
      : '(Không có xác nhận thêm giỏ)';
    const context = `DỮ LIỆU HỆ THỐNG - DANH MỤC:\n${catalog || '(Trống)'}\n\nSẢN PHẨM ĐANG ĐƯỢC NHẮC (nếu có):\n${candidateText}\n\nKẾT QUẢ TRA CỨU SẢN PHẨM PHỤ TRỢ:\n${companionText}\n\n${confirmationText}\n\nLỊCH SỬ AN TOÀN:\n${safeHistory.map((item) => `${item.role === 'model' ? 'Trợ lý' : 'Khách'}: ${item.text}`).join('\n') || '(Không có)'}\n\nHãy trả lời tin nhắn mới nhất. Chỉ gọi addToCart khi quy tắc bắt buộc cho phép.`;
    const contents = [
      ...safeHistory.map((item) => ({ role: item.role, parts: [{ text: item.text }] })),
      { role: 'user', parts: [{ text: `${context}\n\nTIN NHẮN MỚI CỦA KHÁCH: ${message}` }] },
    ];
    const firstResult = await generateGeminiContent({
      apiKey,
      contents,
      tools: CART_TOOL,
      ...(confirmedCart ? { toolConfig: { functionCallingConfig: { mode: 'ANY', allowedFunctionNames: ['addToCart'] } } } : {}),
      maxOutputTokens: 260,
    });
    const functionCall = geminiFunctionCall(firstResult);
    if (!functionCall) {
      if (confirmedCart) {
        return res.json({ success: true, data: { answer: 'Chưa thực hiện được yêu cầu thêm hàng. Bạn kiểm tra giỏ trước khi gửi lại yêu cầu nhé.', action: null } });
      }
      const answer = geminiText(firstResult);
      if (!answer) throw new Error('Gemini không trả về nội dung');
      return res.json({ success: true, data: { answer, action: null } });
    }

    let toolResult;
    const isConfirmedFunction = confirmedCart &&
      Number(functionCall.args?.productId) === confirmedCart.productId &&
      Number(functionCall.args?.quantity) === confirmedCart.quantity;
    const requestedUnit = normalizeSearchText(message).match(/(?:^|\s|\d)(kg|kilogram|can|ki|ky|hop|chai|goi|cai|lon|tui)\b/)?.[1];
    const calledProduct = products.find((product) => Number(product.product_id) === Number(functionCall.args?.productId));
    const unitMismatch = requestedUnit && calledProduct && canonicalUnit(requestedUnit) !== canonicalUnit(calledProduct.unit);
    if (functionCall.name !== 'addToCart' || (confirmedCart ? !isConfirmedFunction : !hasExplicitCartIntent(message))) {
      toolResult = { success: false, message: 'Chưa có yêu cầu thêm giỏ hàng rõ ràng nên không thực hiện thao tác.' };
    } else if (!calledProduct || unitMismatch) {
      toolResult = { success: false, message: 'Đơn vị yêu cầu không khớp đơn vị bán hoặc sản phẩm không tồn tại. Không có dữ liệu quy đổi nên chưa thêm hàng.' };
    } else {
      const productId = Number(functionCall.args?.productId);
      const quantity = Number(functionCall.args?.quantity);
      toolResult = await addProductToCart({ userId, productId, quantity });
    }
    // Thao tác đã có kết quả CSDL: không để lỗi diễn đạt AI làm mất kết quả
    // hoặc khiến người dùng phải xác nhận lại thao tác đã thực hiện.
    let answer = toolResult.success
      ? `Đã thêm ${toolResult.quantity} ${toolResult.unit || 'món'} ${toolResult.productName} vào giỏ hàng.`
      : toolResult.message;
    try {
      const finalResult = await generateGeminiContent({
        apiKey,
        contents: [
          ...contents,
          { role: 'model', parts: [{ functionCall }] },
          { role: 'user', parts: [{ functionResponse: { name: 'addToCart', response: toolResult } }] },
        ],
        maxOutputTokens: 200,
      });
      if (toolResult.success) answer = geminiText(finalResult) || answer;
    } catch (error) {
      console.error('AI tool result reply error:', error.message);
    }
    return res.json({
      success: true,
      data: {
        answer,
        action: toolResult.success ? { type: 'addToCart', productId: Number(functionCall.args?.productId), quantity: toolResult.quantity } : null,
      },
    });
  } catch (error) {
    console.error('AI chat error:', error.message);
    return sendAiFailure(res, error, 'Chưa thể xử lý tin nhắn AI lúc này');
  }
});

router.post('/product-introduction', async (req, res) => {
  const productId = Number(req.body?.productId);
  const question = String(req.body?.question || '').trim();
  const apiKey = process.env.GEMINI_API_KEY;

  if (!productId || !question) {
    return res.status(400).json({ success: false, message: 'Thiếu sản phẩm hoặc câu hỏi' });
  }
  if (!apiKey) {
    return res.status(503).json({
      success: false,
      message: 'Chưa cấu hình GEMINI_API_KEY trong backend/.env',
    });
  }

  try {
    const [rows] = await pool.execute(
      `SELECT p.product_id, p.product_name, p.description, p.price, p.unit, p.stock,
              p.status, c.category_name
       FROM products p
       LEFT JOIN categories c ON c.category_id = p.category_id
       WHERE p.product_id = ? AND p.status = 'active'
       LIMIT 1`,
      [productId],
    );
    if (!rows.length) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy sản phẩm' });
    }

    const product = rows[0];
    const context = `DỮ LIỆU HỆ THỐNG - chỉ dùng những dữ liệu này khi trả lời:
- Tên: ${product.product_name}
- Danh mục: ${product.category_name || 'Chưa có'}
- Mô tả: ${product.description || 'Chưa có'}
- Giá: ${Number(product.price).toLocaleString('vi-VN')} VNĐ/${product.unit || 'sản phẩm'}
 - Tồn kho: ${Number(product.stock)}

YÊU CẦU: Giới thiệu hoặc trả lời câu hỏi về sản phẩm này trong tối đa 100 từ.`;

    const answer = await askGemini({
      apiKey,
      userText: question,
      context,
      maxOutputTokens: 220,
    });
    return res.json({ success: true, data: { answer } });
  } catch (error) {
    console.error('AI product introduction error:', error.message);
    return sendAiFailure(res, error, 'Lỗi khi tạo giới thiệu sản phẩm');
  }
});

// Tư vấn hội thoại có ngữ cảnh toàn bộ danh mục thật. Route này dành cho
// những câu hỏi như "táo chấm gì ngon" hoặc "món nào hợp để nấu canh" thay
// vì chỉ trả về danh sách khớp từ khóa.
router.post('/sales-advice', async (req, res) => {
  const message = String(req.body?.message || '').trim();
  const budget = req.body?.maxPrice == null ? null : Number(req.body.maxPrice);
  if (budget !== null && (!Number.isFinite(budget) || budget < 0)) {
    return res.status(400).json({ success: false, message: 'Ngân sách không hợp lệ' });
  }
  const candidateProductIds = Array.isArray(req.body?.candidateProductIds)
    ? req.body.candidateProductIds.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0)
    : [];
  const apiKey = process.env.GEMINI_API_KEY;
  const normalizedMessage = normalizeSearchText(message);
  const asksPromotion = /khuyen mai|giam gia|uu dai|voucher|ma giam/.test(normalizedMessage);
  const asksPolicy = /chinh sach|phi ship|phi giao|doi tra|bao lau|co.*giao|co.*ship|thanh toan.*(gi|nao|khong)|co.*cod/.test(normalizedMessage);
  if (!message) return res.status(400).json({ success: false, message: 'Thiếu nội dung cần tư vấn' });

  try {
    let promotionContext = '';
    let factualFallback = null;
    if (asksPromotion) {
      const [vouchers] = await pool.execute(
        `SELECT code, description, discount_type, discount_value, min_order_amount, max_discount, expiry_date
         FROM vouchers WHERE status = 'active'
         AND (expiry_date IS NULL OR expiry_date >= CURDATE())
         AND (usage_limit IS NULL OR used_count < usage_limit)
         ORDER BY expiry_date ASC LIMIT 5`,
      );
      promotionContext = `KHUYẾN MÃI THỰC TẾ: ${JSON.stringify(vouchers)}. Đây là mã khả dụng chung, cần kiểm tra điều kiện cho tài khoản/đơn khi thanh toán. Không phải giảm giá trực tiếp mọi sản phẩm.`;
      factualFallback = vouchers.length
        ? `Các mã ưu đãi đang có:\n${vouchers.map((v) => `• ${v.code}: giảm ${v.discount_type === 'percent' ? `${Number(v.discount_value)}%` : `${Number(v.discount_value)} VNĐ`}, đơn tối thiểu ${Number(v.min_order_amount || 0)} VNĐ${v.max_discount ? `, tối đa ${Number(v.max_discount)} VNĐ` : ''}.`).join('\n')}\nĐiều kiện áp dụng cho đơn của bạn sẽ được kiểm tra khi thanh toán.`
        : 'Hiện chưa thấy mã ưu đãi khả dụng trong hệ thống.';
    }
    const policyContext = 'CẤU HÌNH CỬA HÀNG: ứng dụng hỗ trợ đặt giao tận nhà và nhận tại cửa hàng; thanh toán COD/tiền mặt hoặc chuyển khoản. Chưa có dữ liệu chính sách chính thức về phí ship, phạm vi giao, thời gian giao, giờ mở cửa hoặc đổi trả; không suy đoán các thông tin này.';
    if (asksPolicy && !asksPromotion) {
      factualFallback = /doi tra|phi ship|phi giao|bao lau|chinh sach/.test(normalizedMessage)
        ? 'Hệ thống chưa cập nhật chính sách chính thức về thông tin này. Bạn liên hệ cửa hàng để xác nhận giúp mình nhé.'
        : 'Ứng dụng hỗ trợ đặt giao tận nhà, thanh toán COD hoặc chuyển khoản. Khi bạn muốn đặt, mình sẽ kiểm tra giỏ và hỏi thông tin nhận hàng.';
    }
    const [catalogRows] = await pool.execute(
      `SELECT p.product_id, p.product_name, p.description, p.price, p.unit, p.stock, c.category_name
       FROM products p
       LEFT JOIN categories c ON c.category_id = p.category_id
       WHERE p.status = 'active'
       ORDER BY p.product_name
       LIMIT 80`,
    );
    const rows = budget === null ? catalogRows : catalogRows.filter((product) => Number(product.price) <= budget && Number(product.stock) > 0);
    const catalog = rows.map((product) => {
      const description = String(product.description || 'Chưa có mô tả').slice(0, 180);
      return `- ${product.product_name} | danh mục: ${product.category_name || 'Chưa phân loại'} | mô tả: ${description} | giá: ${Number(product.price).toLocaleString('vi-VN')} VNĐ/${product.unit || 'món'} | tồn: ${Number(product.stock)}`;
    }).join('\n');
    const companionResults = companionSearchResult(rows, message);
    const candidates = candidateProductIds.length
      ? rows.filter((product) => candidateProductIds.includes(Number(product.product_id)))
      : [];
    const candidateText = candidates.length
      ? candidates.map((product) => `- ${product.product_name}: ${Number(product.price).toLocaleString('vi-VN')} VNĐ/${product.unit || 'món'}, tồn ${Number(product.stock)}`).join('\n')
      : '(Không có danh sách sản phẩm khớp được gửi kèm)';
    const companionText = companionResults.length
      ? JSON.stringify(companionResults)
      : '(Không có từ khóa sản phẩm phụ trợ cần tra)';

    const context = `DỮ LIỆU HỆ THỐNG - DANH MỤC HIỆN CÓ:\n${catalog || '(Danh mục đang trống)'}\n\nKẾT QUẢ TRA CỨU SẢN PHẨM PHỤ TRỢ:\n${companionText}\n\nKẾT QUẢ SẢN PHẨM KHỚP CÂU HỎI (nếu có):\n${candidateText}\n\nNHIỆM VỤ: Hãy hiểu ý định tư vấn của khách. Nếu khách hỏi cách kết hợp/chế biến, trả lời tự nhiên bằng kiến thức chung nhưng phân biệt rõ gợi ý chung với hàng shop đang có. Nếu khách muốn mua hoặc xem giá, dùng KẾT QUẢ SẢN PHẨM KHỚP CÂU HỎI để trả lời bằng lời tự nhiên, không dùng mẫu câu cố định. Khi cần dữ liệu chưa có, nói rõ chưa thấy dữ liệu thay vì đoán.`;
    if (!apiKey) {
      if (factualFallback) return res.json({ success: true, data: { answer: factualFallback } });
      return res.status(503).json({ success: false, message: 'Chưa cấu hình GEMINI_API_KEY' });
    }
    let answer;
    try {
    answer = await askGemini({
      apiKey,
      userText: message,
      context: `${policyContext}\n${promotionContext}\n${context}${budget === null ? '' : `\nNGÂN SÁCH TỐI ĐA: ${budget} VNĐ. Chỉ đề xuất hàng trong danh sách đã lọc, nêu giá và lý do phù hợp. Tổng giá của mọi combo phải không vượt ngân sách. Không có danh sách phù hợp thì nói rõ, không tự tạo lựa chọn.`}`,
      maxOutputTokens: 260,
    });
    } catch (error) {
      if (!factualFallback) throw error;
      answer = factualFallback;
    }
    return res.json({ success: true, data: { answer } });
  } catch (error) {
    console.error('AI sales advice error:', error.message);
    return sendAiFailure(res, error, 'Chưa thể tạo tư vấn lúc này');
  }
});

router.post('/reply', async (req, res) => {
  const message = String(req.body?.message || '').trim();
  const toolResult = req.body?.toolResult;
  const apiKey = process.env.GEMINI_API_KEY;
  if (!message) return res.status(400).json({ success: false, message: 'Thiếu nội dung chat' });
  if (!apiKey) return res.status(503).json({ success: false, message: 'Chưa cấu hình GEMINI_API_KEY' });
  try {
    // toolResult là kết quả thực tế từ CSDL do Flutter/backend gửi lên.
    // Khi nó rỗng, Gemini nhận mã NO_* để tự diễn đạt linh hoạt thay vì app
    // trả về một câu báo lỗi cố định.
    const context = toolResult == null
      ? 'Không có dữ liệu CSDL đi kèm. Chỉ trả lời tán gẫu/ngắn gọn, không suy đoán thông tin bán hàng.'
      : `KẾT QUẢ TRA CỨU THỰC TẾ:\n${JSON.stringify(toolResult)}`;
    const answer = await askGemini({
      apiKey,
      userText: message,
      context,
      maxOutputTokens: 130,
    });
    return res.json({ success: true, data: { answer } });
  } catch (error) {
    console.error('AI reply error:', error.message);
    return sendAiFailure(res, error, 'Lỗi phản hồi Gemini');
  }
});

module.exports = router;
