import { type z } from 'zod'

type Method = 'get' | 'post' | 'put' | 'patch' | 'delete'

export type Operation = {
  method: Method
  path: string
  id: string
  summary: string
  query?: z.ZodObject
  body?: z.ZodType
  status?: '200' | '201'
  response: z.ZodType | 'file' | 'redirect'
  page?: boolean
  public?: boolean
}
