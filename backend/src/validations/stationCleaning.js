import { z } from 'zod';

export const measurementTypeValues = [
  'sq_ft', 'sq_meter', 'running_ft', 'count', 'number', 'quantity',
  'unit', 'as_available', 'not_applicable', 'service', 'service_based',
];

export const frequencyUnitValues = ['day', 'week', 'fortnight', 'month', 'shift'];

// An area / work item must not be forced to carry sqft. Validation is
// measurement-type aware: numeric measurements require a positive quantity,
// while "as available" / "not applicable" allow an absent quantity.
export const createStationAreaSchema = z.object({
  stationId: z.string().min(1, 'stationId required'),
  name: z.string().min(2, 'name must be at least 2 characters').max(100, 'name must be under 100 characters'),
  areaName: z.string().min(1).max(200).optional(),
  workItem: z.string().max(500).optional(),
  mainArea: z.string().max(200).optional(),
  subArea: z.string().max(200).optional(),
  measurementType: z.enum(measurementTypeValues).optional(),
  quantity: z.union([z.number().positive(), z.null()]).optional(),
  quantityMode: z.enum(['numeric', 'as_available', 'not_applicable']).optional(),
  basicAreaSqFt: z.union([z.number().positive(), z.null()]).optional(),
  frequencyType: z.string().max(100).optional(),
  frequencyValue: z.number().int().positive().optional(),
  frequencyUnit: z.enum(frequencyUnitValues).optional(),
  boqTimesPerPeriod: z.number().int().positive().optional(),
  tenderedAreaPerDay: z.number().optional(),
  cleaningFrequency: z.string().max(100).optional(),
  remarks: z.string().max(1000).optional(),
  status: z.enum(['active', 'inactive']).optional(),
  active: z.boolean().optional(),
  order: z.number().int().min(0).max(999).optional(),
  description: z.string().max(500, 'description must be under 500 characters').optional(),
});

export const createStationZoneSchema = z.object({
  stationId: z.string().min(1),
  areaId: z.string().min(1),
  name: z.string().min(1).max(100).optional(),
  zoneName: z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
}).refine(data => data.name || data.zoneName, {
  message: "Either 'name' or 'zoneName' must be provided",
  path: ['name'],
});

export const createScheduleSchema = z.object({
  stationId: z.string().min(1),
  frequency: z.enum(['daily', 'weekly', 'monthly', 'custom']).optional(),
  shift: z.enum(['Morning', 'Afternoon', 'Night']).optional(),
  daysOfWeek: z.array(z.string()).optional(),
});

export const createStationRunSchema = z.object({
  stationId: z.string().min(1),
  stationName: z.string().min(1),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD format'),
  shift: z.string().min(1),
});

export const submitStationTaskSchema = z.object({
  runInstanceId: z.string().min(1),
  platformNumber: z.string().min(1),
});

export const createStationCleaningFormSchema = z.object({
  stationId: z.string().min(1),
  division: z.string().min(1),
});
