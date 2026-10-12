let nodemailer = null;
let twilio = null;

try {
  nodemailer = require('nodemailer');
} catch (_) {
  nodemailer = null;
}

try {
  twilio = require('twilio');
} catch (_) {
  twilio = null;
}

function canSendEmail() {
  return Boolean(
    nodemailer &&
      process.env.SMTP_HOST &&
      process.env.SMTP_USER &&
      process.env.SMTP_PASS
  );
}

function canSendSms() {
  return Boolean(
    twilio &&
      process.env.TWILIO_ACCOUNT_SID &&
      process.env.TWILIO_AUTH_TOKEN &&
      process.env.TWILIO_FROM_NUMBER
  );
}

async function sendPasswordResetEmail(email, otp) {
  if (!canSendEmail()) {
    if (process.env.ALLOW_OTP_CONSOLE_FALLBACK === 'true') {
      console.log(`[OTP][EMAIL demo] ${email}: ${otp}`);
      return { sent: false, channel: 'console' };
    }
    throw new Error('Chưa cấu hình Gmail SMTP để gửi OTP thật');
  }

  const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT || 587),
    secure: String(process.env.SMTP_SECURE || 'false') === 'true',
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });

  await transporter.sendMail({
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to: email,
    subject: 'Ma OTP dat lai mat khau',
    text: `Ma OTP dat lai mat khau cua ban la: ${otp}. Ma co hieu luc trong 10 phut.`,
  });

  return { sent: true, channel: 'email' };
}

async function sendPasswordResetSms(phone, otp) {
  if (!canSendSms()) {
    if (process.env.ALLOW_OTP_CONSOLE_FALLBACK === 'true') {
      console.log(`[OTP][PHONE demo] ${phone}: ${otp}`);
      return { sent: false, channel: 'console' };
    }
    throw new Error('Chưa cấu hình Twilio để gửi OTP SMS thật');
  }

  const client = twilio(
    process.env.TWILIO_ACCOUNT_SID,
    process.env.TWILIO_AUTH_TOKEN
  );
  await client.messages.create({
    from: process.env.TWILIO_FROM_NUMBER,
    to: phone,
    body: `Ma OTP dat lai mat khau cua ban la: ${otp}. Ma co hieu luc trong 10 phut.`,
  });
  return { sent: true, channel: 'sms' };
}

module.exports = {
  sendPasswordResetEmail,
  sendPasswordResetSms,
};
