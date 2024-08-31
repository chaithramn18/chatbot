You can deploy your own version of the Next.js AI Chatbot to Vercel with one click:

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?demo-title=Next.js+Chat&demo-description=A+full-featured%2C+hackable+Next.js+AI+chatbot+built+by+Vercel+Labs&demo-url=https%3A%2F%2Fchat.vercel.ai%2F&demo-image=%2F%2Fimages.ctfassets.net%2Fe5382hct74si%2F4aVPvWuTmBvzM5cEdRdqeW%2F4234f9baf160f68ffb385a43c3527645%2FCleanShot_2023-06-16_at_17.09.21.png&project-name=Next.js+Chat&repository-name=nextjs-chat&repository-url=https%3A%2F%2Fgithub.com%2Fvercel-labs%2Fai-chatbot&from=templates&skippable-integrations=1&env=OPENAI_API_KEY%2CAUTH_SECRET&envDescription=How+to+get+these+env+vars&envLink=https%3A%2F%2Fgithub.com%2Fvercel-labs%2Fai-chatbot%2Fblob%2Fmain%2F.env.example&teamCreateStatus=hidden&stores=[{"type":"kv"},{"type":"postgres"}])
[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?demo-title=Next.js+Chat&demo-description=A+full-featured%2C+hackable+Next.js+AI+chatbot+built+by+Vercel+Labs&demo-url=https%3A%2F%2Fchat.vercel.ai%2F&demo-image=%2F%2Fimages.ctfassets.net%2Fe5382hct74si%2F4aVPvWuTmBvzM5cEdRdqeW%2F4234f9baf160f68ffb385a43c3527645%2FCleanShot_2023-06-16_at_17.09.21.png&project-name=Next.js+Chat&repository-name=nextjs-chat&repository-url=https%3A%2F%2Fgithub.com%2Fvercel-labs%2Fai-chatbot&from=templates&skippable-integrations=1&env=OPENAI_API_KEY%2CAUTH_SECRET&envDescription=How+to+get+these+env+vars&envLink=https%3A%2F%2Fgithub.com%2Fvercel-labs%2Fai-chatbot%2Fblob%2Fmain%2F.env.example&teamCreateStatus=hidden&stores=[{"type":"kv"}])

## Creating a KV Database Instance

@@ -57,7 +57,6 @@ You will need to use the environment variables [defined in `.env.example`](.env.

```bash
pnpm install
pnpm seed
pnpm dev
```

  39 changes: 30 additions & 9 deletions39  
app/login/actions.ts
Original file line number	Diff line number	Diff line change
@@ -1,14 +1,26 @@
'use server'

import { signIn } from '@/auth'
import { AuthResult } from '@/lib/types'
import { User } from '@/lib/types'
import { AuthError } from 'next-auth'
import { z } from 'zod'
import { kv } from '@vercel/kv'
import { ResultCode } from '@/lib/utils'

export async function getUser(email: string) {
  const user = await kv.hgetall<User>(`user:${email}`)
  return user
}

interface Result {
  type: string
  resultCode: ResultCode
}

export async function authenticate(
  _prevState: AuthResult | undefined,
  _prevState: Result | undefined,
  formData: FormData
) {
): Promise<Result | undefined> {
  try {
    const email = formData.get('email')
    const password = formData.get('password')
@@ -27,24 +39,33 @@ export async function authenticate(
      await signIn('credentials', {
        email,
        password,
        redirectTo: '/'
        redirect: false
      })

      return {
        type: 'success',
        resultCode: ResultCode.UserLoggedIn
      }
    } else {
      return { type: 'error', message: 'Invalid credentials!' }
      return {
        type: 'error',
        resultCode: ResultCode.InvalidCredentials
      }
    }
  } catch (error) {
    if (error instanceof AuthError) {
      switch (error.type) {
        case 'CredentialsSignin':
          return { type: 'error', message: 'Invalid credentials!' }
          return {
            type: 'error',
            resultCode: ResultCode.InvalidCredentials
          }
        default:
          return {
            type: 'error',
            message: 'Something went wrong, please try again!'
            resultCode: ResultCode.UnknownError
          }
      }
    }

    throw error
  }
}
  92 changes: 64 additions & 28 deletions92  
app/signup/actions.ts
Original file line number	Diff line number	Diff line change
@@ -1,15 +1,50 @@
'use server'

import { signIn } from '@/auth'
import { db } from '@vercel/postgres'
import { getStringFromBuffer } from '@/lib/utils'
import { ResultCode, getStringFromBuffer } from '@/lib/utils'
import { z } from 'zod'
import { AuthResult } from '@/lib/types'
import { kv } from '@vercel/kv'
import { getUser } from '../login/actions'
import { AuthError } from 'next-auth'

export async function createUser(
  email: string,
  hashedPassword: string,
  salt: string
) {
  const existingUser = await getUser(email)

  if (existingUser) {
    return {
      type: 'error',
      resultCode: ResultCode.UserAlreadyExists
    }
  } else {
    const user = {
      id: crypto.randomUUID(),
      email,
      password: hashedPassword,
      salt
    }

    await kv.hmset(`user:${email}`, user)

    return {
      type: 'success',
      resultCode: ResultCode.UserCreated
    }
  }
}

interface Result {
  type: string
  resultCode: ResultCode
}

export async function signup(
  _prevState: AuthResult | undefined,
  _prevState: Result | undefined,
  formData: FormData
) {
): Promise<Result | undefined> {
  const email = formData.get('email') as string
  const password = formData.get('password') as string

@@ -34,42 +69,43 @@ export async function signup(
    )
    const hashedPassword = getStringFromBuffer(hashedPasswordBuffer)

    const client = await db.connect()

    try {
      await client.sql`
              INSERT INTO users (email, password, salt)
              VALUES (${email}, ${hashedPassword}, ${salt})
              ON CONFLICT (id) DO NOTHING;
            `
      const result = await createUser(email, hashedPassword, salt)

      await signIn('credentials', {
        email,
        password,
        redirect: false
      })
      if (result.resultCode === ResultCode.UserCreated) {
        await signIn('credentials', {
          email,
          password,
          redirect: false
        })
      }

      return { type: 'success', message: 'Account created!' }
      return result
    } catch (error) {
      const { message } = error as Error

      if (
        message.startsWith('duplicate key value violates unique constraint')
      ) {
        return { type: 'error', message: 'User already exists! Please log in.' }
      if (error instanceof AuthError) {
        switch (error.type) {
          case 'CredentialsSignin':
            return {
              type: 'error',
              resultCode: ResultCode.InvalidCredentials
            }
          default:
            return {
              type: 'error',
              resultCode: ResultCode.UnknownError
            }
        }
      } else {
        return {
          type: 'error',
          message: 'Something went wrong! Please try again.'
          resultCode: ResultCode.UnknownError
        }
      }
    } finally {
      client.release()
    }
  } else {
    return {
      type: 'error',
      message: 'Invalid entries, please try again!'
      resultCode: ResultCode.InvalidCredentials
    }
  }
}
  19 changes: 1 addition & 18 deletions19  
auth.ts
Original file line number	Diff line number	Diff line change
@@ -2,25 +2,8 @@ import NextAuth from 'next-auth'
import Credentials from 'next-auth/providers/credentials'
import { authConfig } from './auth.config'
import { z } from 'zod'
import { sql } from '@vercel/postgres'
import { getStringFromBuffer } from './lib/utils'

interface User {
  id: string
  name: string
  email: string
  password: string
  salt: string
}

async function getUser(email: string): Promise<User | undefined> {
  try {
    const user = await sql<User>`SELECT * FROM users WHERE email=${email}`
    return user.rows[0]
  } catch (error) {
    throw new Error('Failed to fetch user.')
  }
}
import { getUser } from './app/login/actions'

export const { auth, signIn, signOut } = NextAuth({
  ...authConfig,
  14 changes: 9 additions & 5 deletions14  
components/login-form.tsx
Original file line number	Diff line number	Diff line change
@@ -6,26 +6,30 @@ import Link from 'next/link'
import { useEffect } from 'react'
import { toast } from 'sonner'
import { IconSpinner } from './ui/icons'
import { getMessageFromCode } from '@/lib/utils'
import { useRouter } from 'next/navigation'

export default function LoginForm() {
  const router = useRouter()
  const [result, dispatch] = useFormState(authenticate, undefined)

  useEffect(() => {
    if (result) {
      if (result.type === 'error') {
        toast.error(result.message)
        toast.error(getMessageFromCode(result.resultCode))
      } else {
        toast.success(result.message)
        toast.success(getMessageFromCode(result.resultCode))
        router.refresh()
      }
    }
  }, [result])
  }, [result, router])

  return (
    <form
      action={dispatch}
      className="flex flex-col items-center gap-4 space-y-3"
    >
      <div className="w-full flex-1 rounded-lg border bg-white px-6 pb-4 pt-8 shadow-md  dark:bg-zinc-950 md:w-96">
      <div className="w-full flex-1 rounded-lg border bg-white px-6 pb-4 pt-8 shadow-md  md:w-96 dark:bg-zinc-950">
        <h1 className="mb-3 text-2xl font-bold">Please log in to continue.</h1>
        <div className="w-full">
          <div>
@@ -84,7 +88,7 @@ function LoginButton() {

  return (
    <button
      className="flex flex-row justify-center items-center my-4 h-10 w-full rounded-md bg-zinc-900 p-2 text-sm font-semibold text-zinc-100 hover:bg-zinc-800 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-200"
      className="my-4 flex h-10 w-full flex-row items-center justify-center rounded-md bg-zinc-900 p-2 text-sm font-semibold text-zinc-100 hover:bg-zinc-800 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-200"
      aria-disabled={pending}
    >
      {pending ? <IconSpinner /> : 'Log in'}
  9 changes: 5 additions & 4 deletions9  
components/signup-form.tsx
Original file line number	Diff line number	Diff line change
@@ -6,6 +6,7 @@ import Link from 'next/link'
import { useEffect } from 'react'
import { toast } from 'sonner'
import { IconSpinner } from './ui/icons'
import { getMessageFromCode } from '@/lib/utils'
import { useRouter } from 'next/navigation'

export default function SignupForm() {
@@ -15,10 +16,10 @@ export default function SignupForm() {
  useEffect(() => {
    if (result) {
      if (result.type === 'error') {
        toast.error(result.message)
        toast.error(getMessageFromCode(result.resultCode))
      } else {
        toast.success(getMessageFromCode(result.resultCode))
        router.refresh()
        toast.success(result.message)
      }
    }
  }, [result, router])
@@ -28,7 +29,7 @@ export default function SignupForm() {
      action={dispatch}
      className="flex flex-col items-center gap-4 space-y-3"
    >
      <div className="w-full flex-1 rounded-lg border bg-white px-6 pb-4 pt-8 shadow-md dark:bg-zinc-950 md:w-96">
      <div className="w-full flex-1 rounded-lg border bg-white px-6 pb-4 pt-8 shadow-md md:w-96 dark:bg-zinc-950">
        <h1 className="mb-3 text-2xl font-bold">Sign up for an account!</h1>
        <div className="w-full">
          <div>
@@ -85,7 +86,7 @@ function LoginButton() {

  return (
    <button
      className="flex flex-row justify-center items-center my-4 h-10 w-full rounded-md bg-zinc-900 p-2 text-sm font-semibold text-zinc-100 hover:bg-zinc-800 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-200"
      className="my-4 flex h-10 w-full flex-row items-center justify-center rounded-md bg-zinc-900 p-2 text-sm font-semibold text-zinc-100 hover:bg-zinc-800 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-200"
      aria-disabled={pending}
    >
      {pending ? <IconSpinner /> : 'Create account'}
  7 changes: 7 additions & 0 deletions7  
lib/types.ts
Original file line number	Diff line number	Diff line change
@@ -28,3 +28,10 @@ export interface AuthResult {
  type: string
  message: string
}

export interface User extends Record<string, any> {
  id: string
  email: string
  password: string
  salt: string
}
  26 changes: 26 additions & 0 deletions26  
lib/utils.ts
Original file line number	Diff line number	Diff line change
@@ -61,3 +61,29 @@ export const getStringFromBuffer = (buffer: ArrayBuffer) =>
  Array.from(new Uint8Array(buffer))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')

export enum ResultCode {
  InvalidCredentials = 'INVALID_CREDENTIALS',
  InvalidSubmission = 'INVALID_SUBMISSION',
  UserAlreadyExists = 'USER_ALREADY_EXISTS',
  UnknownError = 'UNKNOWN_ERROR',
  UserCreated = 'USER_CREATED',
  UserLoggedIn = 'USER_LOGGED_IN'
}

export const getMessageFromCode = (resultCode: string) => {
  switch (resultCode) {
    case ResultCode.InvalidCredentials:
      return 'Invalid credentials!'
    case ResultCode.InvalidSubmission:
      return 'Invalid submission, please try again!'
    case ResultCode.UserAlreadyExists:
      return 'User already exists, please log in!'
    case ResultCode.UserCreated:
      return 'User created, welcome!'
    case ResultCode.UnknownError:
      return 'Something went wrong, please try again!'
    case ResultCode.UserLoggedIn:
      return 'Logged in!'
  }
}
  1 change: 0 additions & 1 deletion1  
package.json
Original file line number	Diff line number	Diff line change
@@ -26,7 +26,6 @@
    "@vercel/analytics": "^1.1.2",
    "@vercel/kv": "^1.0.1",
    "@vercel/og": "^0.6.2",
    "@vercel/postgres": "^0.7.2",
    "ai": "^3.0.12",
    "class-variance-authority": "^0.7.0",
    "clsx": "^2.1.0",
