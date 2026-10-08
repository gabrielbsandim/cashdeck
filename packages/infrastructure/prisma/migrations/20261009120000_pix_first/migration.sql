-- CreateEnum
CREATE TYPE "PaymentMethod" AS ENUM ('PIX', 'BOLETO');

-- AlterTable
ALTER TABLE "bills" ADD COLUMN     "pix_code" TEXT;

-- AlterTable
ALTER TABLE "payment_attempts" ADD COLUMN     "method" "PaymentMethod" NOT NULL DEFAULT 'BOLETO';

