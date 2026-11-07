const mysql = require("mysql2/promise"); // Đảm bảo đã require thư viện
require("dotenv").config();

// Khởi tạo biến pool
const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT || 4000,
  // Local MySQL may run without TLS; preserve the existing cloud default.
  ...(process.env.DB_SSL === "false"
    ? {}
    : { ssl: { rejectUnauthorized: false } }),
  timezone: '+07:00',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

// TIMESTAMP and DATETIME reporting use one explicit business timezone.
pool.pool.on('connection', (connection) => connection.query("SET time_zone = '+07:00'"));

// Xuất biến pool ra để server.js sử dụng
module.exports = pool;
