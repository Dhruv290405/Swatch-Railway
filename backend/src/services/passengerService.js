import jwt from 'jsonwebtoken';
import { db } from '../database/index.js';
import { NotFoundError, ValidationError, FirestoreError } from '../errors/index.js';
import config from '../config/index.js';
import otpStore from '../utils/otpStore.js';

class PassengerService {
  async submitTaskFeedback(userData, body) {
    const { taskId, passengerScore, passengerPhone, feedbackText } = body;
    if (!taskId) throw new ValidationError('taskId is required');
    const taskRef = db.collection('task_instances').doc(taskId);
    const doc = await taskRef.get();
    if (!doc.exists) throw new NotFoundError('Task not found');
    const taskData = doc.data();
    const supScore = taskData.supervisorScore || 0;
    const pScore = Number(passengerScore);
    if (isNaN(pScore)) throw new ValidationError('passengerScore must be a valid number');
    const consolidatedScore = (pScore * 0.7) + (supScore * 0.3);
    await taskRef.update({
      passengerScore: pScore,
      passengerPhone: passengerPhone || '',
      passengerFeedback: feedbackText || '',
      consolidatedScore,
      feedbackReceivedAt: new Date().toISOString()
    });
    return { success: true, message: 'Feedback submitted', consolidatedScore };
  }

  async submitPublicFeedback(body) {
    const { passengerName, mobileNumber, coachNo, ratings, remarks, runInstanceId } = body;

    if (!runInstanceId || !coachNo || !ratings) {
      throw new ValidationError('Run Instance ID, Coach No, and Ratings are required.');
    }

    const { cleanliness, toiletHygiene, linenQuality, security, staffBehaviour } = ratings;
    if (
      cleanliness === undefined ||
      toiletHygiene === undefined ||
      linenQuality === undefined ||
      security === undefined ||
      staffBehaviour === undefined
    ) {
      throw new ValidationError('All 5 rating parameters must be provided.');
    }

    // RunInstance is the authoritative collection (written by the runs API).
    // obhsRunInstances was a client-side mirror that is no longer written.
    const runDoc = await db.collection('RunInstance').doc(runInstanceId).get();
    if (!runDoc.exists) throw new NotFoundError('Journey not found.');
    const runData = runDoc.data();

    const totalStars =
      Number(cleanliness) +
      Number(toiletHygiene) +
      Number(linenQuality) +
      Number(security) +
      Number(staffBehaviour);

    const overallRating = parseFloat((totalStars / 5).toFixed(2));

    const feedbackRef = db.collection('obhs_feedbacks').doc();

    const feedbackData = {
      feedbackId: feedbackRef.id,
      feedbackType: 'QR_PASSENGER',
      runInstanceId: runInstanceId,
      trainNo: runData.trainNo || 'UNKNOWN',
      trainName: runData.trainName || '',
      coachNo: coachNo,
      passengerName: passengerName || 'Anonymous',
      mobileNumber: mobileNumber || 'N/A',
      remarks: remarks || '',
      ratings: {
        cleanliness: Number(cleanliness),
        toiletHygiene: Number(toiletHygiene),
        linenQuality: Number(linenQuality),
        security: Number(security),
        staffBehaviour: Number(staffBehaviour)
      },
      overallRating: overallRating,
      source: 'QR_CODE',
      createdAt: new Date().toISOString(),
      timestamp: Date.now()
    };

    await feedbackRef.set(feedbackData);

    return {
      success: true,
      message: 'Thank you for your valuable feedback!',
      overallRating: overallRating
    };
  }

  async getFeedbackList(filters = {}) {
    const { taskId, trainNo, coachNo } = filters;
    if (taskId) {
      const doc = await db.collection('task_instances').doc(taskId).get();
      if (!doc.exists) throw new NotFoundError('Task not found');
      return { feedback: doc.data() };
    }
    let query = db.collection('task_instances');
    if (trainNo) query = query.where('trainNo', '==', trainNo);
    if (coachNo) query = query.where('coachNo', '==', coachNo);
    const snapshot = await query.limit(200).get();
    const feedbacks = [];
    snapshot.forEach(doc => {
      const data = doc.data();
      if (data.passengerScore !== undefined || data.passengerFeedback) {
        feedbacks.push({ id: doc.id, ...data });
      }
    });
    return { count: feedbacks.length, feedbacks };
  }

  async sendOtp(phone) {
    if (!phone) throw new ValidationError('Phone number is required');

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    await otpStore.set(phone, otp);

    const TWO_FACTOR_API_KEY = config.sms.twoFactorApiKey;
    if (!TWO_FACTOR_API_KEY) {
      throw new Error('2Factor API key not configured');
    }

    const url = `https://2factor.in/API/V1/${TWO_FACTOR_API_KEY}/VOICE/${phone}/${otp}`;
    const axios = (await import('axios')).default;
    const response = await axios.get(url);

    if (response.data.Status === "Success") {
      return { success: true, message: "OTP has been sent to passenger mobile number." };
    }
    throw new Error(response.data.Details || "Failed to send voice OTP via 2Factor");
  }

  async verifyOtp(phone, otp) {
    if (!phone || !otp) {
      throw new ValidationError("Phone number and OTP are required.");
    }

    const storedOtp = await otpStore.get(phone);
    if (!storedOtp) {
      throw new ValidationError("OTP expired or not requested. Please try again.");
    }

    const attemptKey = `ATTEMPT_${phone}`;
    const attempts = (await otpStore.get(attemptKey)) || 0;
    if (attempts >= 5) {
      throw new ValidationError("Too many attempts. Please request a new OTP.");
    }

    if (storedOtp !== otp) {
      await otpStore.set(attemptKey, attempts + 1);
      throw new ValidationError("Invalid OTP. Please check and try again.");
    }

    await Promise.all([
      otpStore.delete(phone),
      otpStore.delete(attemptKey)
    ]);

    const token = jwt.sign({ phone, purpose: 'passenger' }, config.jwtSecret, { expiresIn: '1h' });
    return { success: true, message: "Passenger mobile number verified successfully.", token };
  }

  async createPassengerTask(body) {
    const { trainNo, coachNo, seatNo, taskType, description } = body;

    if (!trainNo || !coachNo || !taskType) {
      throw new ValidationError("Train No, Coach No, and Task Type are required.");
    }

    const taskId = `pass_${Date.now()}`;
    const taskData = {
      taskId, trainNo, coachNo,
      seatNo: seatNo || 'N/A',
      taskType, description: description || '',
      status: 'OPEN', source: 'PASSENGER',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    await db.collection('passenger_tasks').doc(taskId).set(taskData);
    return { success: true, message: "Task created successfully.", taskId };
  }

  async getPassengerTasks(query = {}) {
    const { trainNo } = query;
    let firestoreQuery = db.collection('passenger_tasks');
    if (trainNo) firestoreQuery = firestoreQuery.where('trainNo', '==', trainNo);
    const snapshot = await firestoreQuery.limit(200).get();
    const tasks = [];
    snapshot.forEach(doc => tasks.push({ uid: doc.id, ...doc.data() }));
    tasks.sort((a, b) => {
      const dateA = a.createdAt ? new Date(a.createdAt) : new Date(0);
      const dateB = b.createdAt ? new Date(b.createdAt) : new Date(0);
      return dateB - dateA;
    });
    return { success: true, count: tasks.length, tasks };
  }

  async getTrainCoaches(trainNo) {
    const runsSnap = await db.collection('RunInstance')
      .where('trainNo', '==', trainNo)
      .limit(200).get();

    if (runsSnap.empty) {
      return { success: true, coaches: [] };
    }

    const coachSet = new Set();
    runsSnap.forEach(doc => {
      const runData = doc.data();
      const status = (runData.status || '').toUpperCase();
      
      // Skip completed or inactive runs
      if (['COMPLETED', 'FINISHED', 'CLOSED', 'INACTIVE'].includes(status)) {
        return;
      }

      if (runData.coaches && Array.isArray(runData.coaches)) {
        runData.coaches.forEach(c => {
          const val = c.coachNumber || c.coachPosition || c.coachNo;
          if (val !== undefined && val !== null && val !== '') {
            coachSet.add(String(val).trim());
          }
        });
      }
    });

    const sortedCoaches = Array.from(coachSet).sort((a, b) => {
      return a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });
    });
    return { success: true, coaches: sortedCoaches };
  }
}

export const passengerService = new PassengerService();
