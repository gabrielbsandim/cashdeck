import {
  monthlyRecapQuerySchema,
  monthlyRecapSchema,
} from '@cashdeck/application'
import { type Operation } from '@/server/api/openapi-operation'

export const RECAP_OPERATIONS: Operation[] = [
  {
    method: 'get',
    path: '/recaps/latest',
    id: 'getLatestRecap',
    summary: 'The recap of the last month that closed, with its AI story',
    query: monthlyRecapQuerySchema,
    response: monthlyRecapSchema,
  },
  {
    method: 'get',
    path: '/recaps/{month}',
    id: 'getMonthlyRecap',
    summary:
      'A closed month (YYYY-MM) told in figures: money in and out, top category, changes, savings rate, net worth and a short story',
    query: monthlyRecapQuerySchema,
    response: monthlyRecapSchema,
  },
]
