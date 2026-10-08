import { type ptBR } from './pt-BR'

type Widen<T> = { [K in keyof T]: T[K] extends string ? string : Widen<T[K]> }

export type Messages = Widen<typeof ptBR>
