-- Two people of one household can each hold an account at the same bank.
ALTER TABLE "accounts" ADD COLUMN "holder" TEXT;
