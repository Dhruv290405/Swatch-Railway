import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { db, admin } from '../database/index.js';
import { AppError, AuthenticationError, ForbiddenError, NotFoundError, ValidationError } from '../errors/index.js';
import config from '../config/index.js';
import logger from '../logger/index.js';
import { notificationService } from '../notifications/index.js';
import otpStore from '../utils/otpStore.js';
import { backfillContractType } from '../utils/contractTypeResolver.js';

class AuthService {
  async sendOtp(phone) {
    if (!phone) {
      throw new ValidationError('Phone number is required');
    }
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    await otpStore.set(phone, otp);
    await notificationService.sendOtpSms(phone, otp);
    logger.info('Auth', `(2Factor) OTP sent to ${phone}`);
    return { success: true, message: "OTP has been sent to your mobile number." };
  }

  async verifyOtp(phone, otp) {
    if (!phone || !otp) {
      throw new ValidationError("Phone number and OTP are required.");
    }
    const storedOtp = await otpStore.get(phone);
    if (!storedOtp) {
      throw new ValidationError("OTP expired or not requested. Please try again.");
    }
    if (storedOtp !== otp) {
      throw new ValidationError("Invalid OTP. Please check and try again.");
    }
    await otpStore.delete(phone);
    const usersRef = db.collection('users');
    const snapshot = await usersRef.where('mobile', '==', phone).limit(1).get();
    if (snapshot.empty) {
      throw new NotFoundError("This mobile number is not registered in our database.");
    }
    const userData = snapshot.docs[0].data();
    if (userData.status !== 'APPROVED') {
      throw new ForbiddenError(`Your account status is ${userData.status}. Please contact Admin for access.`);
    }
    let entityDetails = null;
    if (userData.userType === 'contractor' && userData.entityId) {
      const entityDoc = await db.collection('entities').doc(userData.entityId).get();
      if (entityDoc.exists) {
        entityDetails = entityDoc.data();
        userData.entityDetails = entityDetails;
      }
    }
    const token = jwt.sign(
      { uid: userData.uid, role: userData.role, userType: userData.userType, fullName: userData.fullName, email: userData.email, mobile: userData.mobile, zone: userData.zone, division: userData.division, depot: userData.depot, entityId: userData.entityId },
      config.jwtSecret,
      { expiresIn: '7d' }
    );
    await backfillContractType(userData);
    delete userData.password;
    logger.info('Auth', `(Login) Success via 2Factor OTP for ${phone}`);
    return { success: true, message: "Login Successful", token, user: userData };
  }

  async sendEmailOtp(email) {
    if (!email) {
      throw new ValidationError("Email is required.");
    }
    const userSnapshot = await db.collection('users').where('email', '==', email).limit(1).get();
    if (userSnapshot.empty) {
      throw new NotFoundError("This email is not registered.");
    }
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    await otpStore.set(email, otp);
    logger.info('Auth', `(Resend) Generated OTP for ${email}`);
    await notificationService.sendOtpEmail(email, otp, 'login');
    return { message: "OTP has been sent to your email." };
  }

  async verifyEmailOtp(email, otp) {
    if (!email || !otp) {
      throw new ValidationError("Email and OTP are required.");
    }
    const storedOtp = await otpStore.get(email);
    if (!storedOtp) {
      throw new ValidationError("OTP expired or not requested. Please try again.");
    }
    if (storedOtp !== otp) {
      throw new ValidationError("Invalid OTP. Please check and try again.");
    }
    await otpStore.delete(email);
    const usersRef = db.collection('users');
    const snapshot = await usersRef.where('email', '==', email).limit(1).get();
    if (snapshot.empty) {
      throw new NotFoundError("Record not found in database.");
    }
    const userData = snapshot.docs[0].data();
    if (userData.status !== 'APPROVED') {
      throw new ForbiddenError(`Your account is ${userData.status}. Contact admin.`);
    }
    let entityDetails = null;
    if (userData.userType === 'contractor' && userData.entityId) {
      const entityDoc = await db.collection('entities').doc(userData.entityId).get();
      if (entityDoc.exists) {
        entityDetails = entityDoc.data();
        userData.entityDetails = entityDetails;
      }
    }
    const token = jwt.sign(
      { uid: userData.uid, role: userData.role, userType: userData.userType, fullName: userData.fullName, email: userData.email, zone: userData.zone, division: userData.division, depot: userData.depot, entityId: userData.entityId },
      config.jwtSecret,
      { expiresIn: '7d' }
    );
    await backfillContractType(userData);
    delete userData.password;
    logger.info('Auth', `(Login) Success via Resend OTP for ${email}`);
    return { message: "Login Successful", token, user: userData };
  }

  async login(email, password) {
    if (!email || !password) {
      throw new ValidationError("Email and Password are required.");
    }
    const normalizedEmail = email.trim().toLowerCase();
    const usersRef = db.collection('users');
    const snapshot = await usersRef.where('email', '==', normalizedEmail).get();
    if (snapshot.empty) {
      logger.info('Auth', `(Login) Failed login: Email not found ${normalizedEmail}`);
      throw new AuthenticationError("Invalid credentials.");
    }
    const docs = snapshot.docs;
    docs.sort((a, b) => {
      const aTime = a.data().createdAt || '';
      const bTime = b.data().createdAt || '';
      return bTime.localeCompare(aTime);
    });
    const userData = docs[0].data();
    const storedPassword = userData.password || '';
    const isBcrypt = storedPassword.startsWith('$2');
    const passwordValid = isBcrypt ? bcrypt.compareSync(password, storedPassword) : storedPassword === password;
    if (!passwordValid) {
      logger.info('Auth', `(Login) Failed login: Password mismatch for ${normalizedEmail}`);
      throw new AuthenticationError("Invalid credentials.");
    }
    if (userData.status !== 'APPROVED') {
      logger.info('Auth', `(Login) Failed login for ${normalizedEmail}: Status is ${userData.status}`);
      throw new ForbiddenError(`Your account status is: ${userData.status}. Contact admin.`);
    }
    let entityDetails = null;
    if (userData.userType === 'contractor' && userData.entityId) {
      const entityDoc = await db.collection('entities').doc(userData.entityId).get();
      if (entityDoc.exists) {
        entityDetails = entityDoc.data();
        userData.entityDetails = entityDetails;
      }
    }
    let activeRunInstanceId = null;
    try {
      if (userData.uid) {
        const runInstanceSnapshot = await db.collection('RunInstance')
          .where('status', 'in', ['PLANNED', 'ALLOCATED', 'READY', 'Active', 'ACTIVE', 'active', 'Scheduled', 'scheduled', 'Running', 'running'])
          .limit(200)
          .get();
        for (const doc of runInstanceSnapshot.docs) {
          const runData = doc.data();
          if (runData.coaches && Array.isArray(runData.coaches)) {
            const isWorkerAssigned = runData.coaches.some(coach =>
              coach.workerId === userData.uid || coach.janitorId === userData.uid || coach.attendantId === userData.uid);
            if (isWorkerAssigned) {
              activeRunInstanceId = runData.runInstanceId || doc.id;
              break;
            }
          }
        }
      }
    } catch (runError) {
      logger.error('Auth', '(Login) Optional RunInstance fetch failed:', runError);
    }
    userData.activeRunInstanceId = activeRunInstanceId;
    const customAppToken = jwt.sign(
      { uid: userData.uid, role: userData.role, userType: userData.userType, fullName: userData.fullName, email: userData.email, zone: userData.zone, division: userData.division, depot: userData.depot, entityId: userData.entityId, activeRunInstanceId: activeRunInstanceId },
      config.jwtSecret,
      { expiresIn: '7d' }
    );
    logger.info('Auth', `(Login) Successful login for ${normalizedEmail}, ActiveRunInstance: ${activeRunInstanceId}`);
    await backfillContractType(userData);
    delete userData.password;
    return { message: "Login Successful", token: customAppToken, user: userData };
  }

  async loginWithMobile(mobile, password) {
    if (!mobile || !password) {
      throw new ValidationError("Mobile number and Password are required.");
    }
    const usersRef = db.collection('users');
    const snapshot = await usersRef.where('mobile', '==', mobile).limit(1).get();
    if (snapshot.empty) {
      logger.info('Auth', `(Login) Failed login: Mobile not found ${mobile}`);
      throw new AuthenticationError("Invalid credentials.");
    }
    const userData = snapshot.docs[0].data();
    const storedPassword = userData.password || '';
    const isBcrypt = storedPassword.startsWith('$2');
    const passwordValid = isBcrypt ? bcrypt.compareSync(password, storedPassword) : storedPassword === password;
    if (!passwordValid) {
      logger.info('Auth', `(Login) Failed login: Password mismatch for mobile ${mobile}`);
      throw new AuthenticationError("Invalid credentials.");
    }
    if (userData.status !== 'APPROVED') {
      logger.info('Auth', `(Login) Failed login for mobile ${mobile}: Status is ${userData.status}`);
      throw new ForbiddenError(`Your account status is: ${userData.status}. Contact admin.`);
    }
    let entityDetails = null;
    if (userData.userType === 'contractor' && userData.entityId) {
      const entityDoc = await db.collection('entities').doc(userData.entityId).get();
      if (entityDoc.exists) {
        entityDetails = entityDoc.data();
        userData.entityDetails = entityDetails;
      }
    }
    const customAppToken = jwt.sign(
      { uid: userData.uid, role: userData.role, userType: userData.userType, fullName: userData.fullName, email: userData.email, mobile: userData.mobile, zone: userData.zone, division: userData.division, depot: userData.depot, entityId: userData.entityId },
      config.jwtSecret,
      { expiresIn: '7d' }
    );
    logger.info('Auth', `(Login) Successful login for mobile ${mobile}`);
    await backfillContractType(userData);
    delete userData.password;
    return { message: "Login Successful", token: customAppToken, user: userData };
  }

  async sendForgotPasswordOtp(mobile) {
    if (!mobile) {
      throw new ValidationError("Mobile number is required.");
    }
    if (!/^\d{10}$/.test(mobile)) {
      throw new ValidationError("Invalid mobile number. Must be 10 digits.");
    }
    const usersRef = db.collection('users');
    const snapshot = await usersRef.where('mobile', '==', mobile).limit(1).get();
    if (snapshot.empty) {
      throw new NotFoundError("Mobile number not registered.");
    }
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    await otpStore.set(`RESET_${mobile}`, otp);
    if (!config.sms.twoFactorApiKey && !config.sms.twilio?.phoneNumber) {
      logger.error('Auth', 'No OTP delivery provider configured (2Factor or Twilio)');
      throw new AppError("OTP delivery service not configured", 500);
    }
    await notificationService.sendPasswordResetOtp(mobile, otp);
    logger.info('Auth', `(ForgotPwd) OTP voice/SMS sent to ${mobile}`);
    return { message: "OTP sent to your registered mobile number." };
  }

  async verifyForgotPasswordOtp(mobile, otp) {
    if (!mobile || !otp) {
      throw new ValidationError("Mobile number and OTP are required.");
    }
    const storedOtp = await otpStore.get(`RESET_${mobile}`);
    if (!storedOtp) {
      throw new ValidationError("OTP expired or invalid request.");
    }
    if (storedOtp !== otp) {
      throw new ValidationError("Invalid OTP.");
    }
    await otpStore.delete(`RESET_${mobile}`);
    const usersRef = db.collection('users');
    const snapshot = await usersRef.where('mobile', '==', mobile).limit(1).get();
    if (snapshot.empty) {
      throw new NotFoundError("User not found.");
    }
    const userDoc = snapshot.docs[0];
    const resetToken = jwt.sign({ uid: userDoc.id, purpose: 'password_reset' }, config.jwtSecret, { expiresIn: '10m' });
    logger.info('Auth', `(ForgotPwd) OTP Verified for ${mobile}. Sending Reset Token.`);
    return { message: "OTP Verified. Please proceed to reset password.", resetToken };
  }

  async resetPassword(newPassword, resetToken) {
    if (!newPassword || !resetToken) {
      throw new ValidationError("New Password and Reset Token are required.");
    }
    let decoded;
    try {
      decoded = jwt.verify(resetToken, config.jwtSecret);
    } catch (err) {
      throw new ForbiddenError("Invalid or expired reset session. Please try again.");
    }
    if (decoded.purpose !== 'password_reset') {
      throw new ForbiddenError("Invalid token type.");
    }
    const uid = decoded.uid;
    await db.collection('users').doc(uid).update({ password: newPassword, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    logger.info('Auth', `(ForgotPwd) Password reset success for User UID: ${uid}`);
    return { message: "Password has been reset successfully. You can now login." };
  }

  async sendForgotPasswordEmailOtp(email) {
    if (!email) {
      throw new ValidationError("Email is required.");
    }
    const usersRef = db.collection('users');
    const snapshot = await usersRef.where('email', '==', email).limit(1).get();
    if (snapshot.empty) {
      throw new NotFoundError("Email address not registered.");
    }
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    await otpStore.set(`RESET_EMAIL_${email}`, otp);
    await notificationService.sendOtpEmail(email, otp, 'reset');
    logger.info('Auth', `(ForgotPwd) Email OTP sent to ${email}`);
    return { message: "OTP sent to your registered email." };
  }

  async verifyForgotPasswordEmailOtp(email, otp) {
    if (!email || !otp) {
      throw new ValidationError("Email and OTP are required.");
    }
    const storedOtp = await otpStore.get(`RESET_EMAIL_${email}`);
    if (!storedOtp) {
      throw new ValidationError("OTP expired or invalid request.");
    }
    if (storedOtp !== otp) {
      throw new ValidationError("Invalid OTP.");
    }
    await otpStore.delete(`RESET_EMAIL_${email}`);
    const usersRef = db.collection('users');
    const snapshot = await usersRef.where('email', '==', email).limit(1).get();
    if (snapshot.empty) {
      throw new NotFoundError("User not found.");
    }
    const userDoc = snapshot.docs[0];
    const resetToken = jwt.sign({ uid: userDoc.id, purpose: 'password_reset' }, config.jwtSecret, { expiresIn: '10m' });
    logger.info('Auth', `(ForgotPwd) Email OTP Verified for ${email}. Sending Token.`);
    return { message: "OTP Verified. Please proceed to reset password.", resetToken };
  }

  async updateProfile(userId, updateData) {
    const allowedFields = ['fullName', 'mobile', 'designation', 'profilePhoto', 'email'];
    const ref = db.collection('users').doc(userId);
    const doc = await ref.get();
    if (!doc.exists) throw new NotFoundError('User not found');

    const data = {};
    for (const field of allowedFields) {
      if (updateData[field] !== undefined) {
        if (field === 'mobile' && !/^\d{10}$/.test(updateData.mobile)) {
          throw new ValidationError('Invalid mobile number. Must be 10 digits.');
        }
        data[field] = updateData[field];
      }
    }

    if (Object.keys(data).length === 0) throw new ValidationError('No fields to update');

    data.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    data.updatedBy = userId;

    await ref.update(data);
    const updated = await ref.get();
    const userData = updated.data();
    await backfillContractType(userData);
    delete userData.password;
    return { message: 'Profile updated successfully', user: userData };
  }

  async changePassword(uid, currentPassword, newPassword, userDetails) {
    if (!currentPassword || !newPassword) {
      throw new ValidationError('Current password and new password are required.');
    }
    if (newPassword.length < 6) {
      throw new ValidationError('New password must be at least 6 characters.');
    }
    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      throw new NotFoundError('User not found');
    }
    const userData = userDoc.data();
    if (userData.password !== currentPassword) {
      throw new ForbiddenError('Current password is incorrect.');
    }
    await userRef.update({ password: newPassword, updatedAt: new Date().toISOString() });
    try {
      await admin.auth().updateUser(uid, { password: newPassword });
    } catch (authError) {
      // Swallow Firebase Auth update error
    }
    const auditRef = db.collection('auditLogs').doc();
    await auditRef.set({
      logId: auditRef.id,
      action: 'PASSWORD_CHANGED',
      performedBy: uid,
      performedByName: userDetails.fullName,
      targetUser: uid,
      targetUserName: userDetails.fullName,
      timestamp: new Date().toISOString(),
      details: 'User changed their password'
    });
    return { message: 'Password changed successfully.' };
  }
}

export const authService = new AuthService();
