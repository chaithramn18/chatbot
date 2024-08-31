import { type Metadata } from 'next'	import { type Metadata } from 'next'
import { notFound, redirect } from 'next/navigation'	import { notFound, redirect } from 'next/navigation'
import { auth } from '@/auth'	import { auth } from '@/auth'
import { getChat, getMissingKeys } from '@/app/actions'	import { getChat, getMissingKeys } from '@/app/actions'
import { Chat } from '@/components/chat'	import { Chat } from '@/components/chat'
import { AI } from '@/lib/chat/actions'	import { AI } from '@/lib/chat/actions'
import { Session } from '@/lib/types'	import { Session } from '@/lib/types'
export interface ChatPageProps {	export interface ChatPageProps {
  params: {	  params: {
    id: string	    id: string
  }	  }
}	}
export async function generateMetadata({	export async function generateMetadata({
  params	  params
}: ChatPageProps): Promise<Metadata> {	}: ChatPageProps): Promise<Metadata> {
  const session = await auth()	  const session = await auth()
  if (!session?.user) {	  if (!session?.user) {
    return {}	    return {}
  }	  }


  const chat = await getChat(params.id, session.user.id)	  const chat = await getChat(params.id, session.user.id)
  return {	
    title: chat?.title.toString().slice(0, 50) ?? 'Chat'	  if (!chat || 'error' in chat) {
    redirect('/')
  } else {
    return {
      title: chat?.title.toString().slice(0, 50) ?? 'Chat'
    }
  }	  }
}	}


export default async function ChatPage({ params }: ChatPageProps) {	export default async function ChatPage({ params }: ChatPageProps) {
  const session = (await auth()) as Session	  const session = (await auth()) as Session
  const missingKeys = await getMissingKeys()	  const missingKeys = await getMissingKeys()
  if (!session?.user) {	  if (!session?.user) {
    redirect(`/login?next=/chat/${params.id}`)	    redirect(`/login?next=/chat/${params.id}`)
  }	  }
  const userId = session.user.id as string	  const userId = session.user.id as string
  const chat = await getChat(params.id, userId)	  const chat = await getChat(params.id, userId)


  if (!chat) {	  if (!chat || 'error' in chat) {
    redirect('/')	    redirect('/')
  }	  } else {
    if (chat?.userId !== session?.user?.id) {
      notFound()
    }


  if (chat?.userId !== session?.user?.id) {	    return (
    notFound()	      <AI initialAIState={{ chatId: chat.id, messages: chat.messages }}>
        <Chat
          id={chat.id}
          session={session}
          initialMessages={chat.messages}
          missingKeys={missingKeys}
        />
      </AI>
    )
  }	  }

  return (	
    <AI initialAIState={{ chatId: chat.id, messages: chat.messages }}>	
      <Chat	
        id={chat.id}	
        session={session}	
        initialMessages={chat.messages}	
        missingKeys={missingKeys}	
      />	
    </AI>	
  )	
}	}
  18 changes: 17 additions & 1 deletion18  
app/actions.ts
Original file line number	Original file line	Diff line number	Diff line change
@@ -8,10 +8,18 @@ import { auth } from '@/auth'
import { type Chat } from '@/lib/types'	import { type Chat } from '@/lib/types'


export async function getChats(userId?: string | null) {	export async function getChats(userId?: string | null) {
  const session = await auth()

  if (!userId) {	  if (!userId) {
    return []	    return []
  }	  }


  if (userId !== session?.user?.id) {
    return {
      error: 'Unauthorized'
    }
  }

  try {	  try {
    const pipeline = kv.pipeline()	    const pipeline = kv.pipeline()
    const chats: string[] = await kv.zrange(`user:chat:${userId}`, 0, -1, {	    const chats: string[] = await kv.zrange(`user:chat:${userId}`, 0, -1, {
@@ -31,6 +39,14 @@ export async function getChats(userId?: string | null) {
}	}


export async function getChat(id: string, userId: string) {	export async function getChat(id: string, userId: string) {
  const session = await auth()

  if (userId !== session?.user?.id) {
    return {
      error: 'Unauthorized'
    }
  }

  const chat = await kv.hgetall<Chat>(`chat:${id}`)	  const chat = await kv.hgetall<Chat>(`chat:${id}`)


  if (!chat || (userId && chat.userId !== userId)) {	  if (!chat || (userId && chat.userId !== userId)) {
@@ -49,7 +65,7 @@ export async function removeChat({ id, path }: { id: string; path: string }) {
    }	    }
  }	  }


  //Convert uid to string for consistent comparison with session.user.id	  // Convert uid to string for consistent comparison with session.user.id
  const uid = String(await kv.hget(`chat:${id}`, 'userId'))	  const uid = String(await kv.hget(`chat:${id}`, 'userId'))


  if (uid !== session?.user?.id) {	  if (uid !== session?.user?.id) {
  41 changes: 23 additions & 18 deletions41  
components/sidebar-list.tsx
Original file line number	Original file line	Diff line number	Diff line change
@@ -2,6 +2,7 @@ import { clearChats, getChats } from '@/app/actions'
import { ClearHistory } from '@/components/clear-history'	import { ClearHistory } from '@/components/clear-history'
import { SidebarItems } from '@/components/sidebar-items'	import { SidebarItems } from '@/components/sidebar-items'
import { ThemeToggle } from '@/components/theme-toggle'	import { ThemeToggle } from '@/components/theme-toggle'
import { redirect } from 'next/navigation'
import { cache } from 'react'	import { cache } from 'react'


interface SidebarListProps {	interface SidebarListProps {
@@ -16,23 +17,27 @@ const loadChats = cache(async (userId?: string) => {
export async function SidebarList({ userId }: SidebarListProps) {	export async function SidebarList({ userId }: SidebarListProps) {
  const chats = await loadChats(userId)	  const chats = await loadChats(userId)


  return (	  if (!chats || 'error' in chats) {
    <div className="flex flex-1 flex-col overflow-hidden">	    redirect('/')
      <div className="flex-1 overflow-auto">	  } else {
        {chats?.length ? (	    return (
          <div className="space-y-2 px-2">	      <div className="flex flex-1 flex-col overflow-hidden">
            <SidebarItems chats={chats} />	        <div className="flex-1 overflow-auto">
          </div>	          {chats?.length ? (
        ) : (	            <div className="space-y-2 px-2">
          <div className="p-8 text-center">	              <SidebarItems chats={chats} />
            <p className="text-sm text-muted-foreground">No chat history</p>	            </div>
          </div>	          ) : (
        )}	            <div className="p-8 text-center">
              <p className="text-sm text-muted-foreground">No chat history</p>
            </div>
          )}
        </div>
        <div className="flex items-center justify-between p-4">
          <ThemeToggle />
          <ClearHistory clearChats={clearChats} isEnabled={chats?.length > 0} />
        </div>
      </div>	      </div>
      <div className="flex items-center justify-between p-4">	    )
        <ThemeToggle />	  }
        <ClearHistory clearChats={clearChats} isEnabled={chats?.length > 0} />	
      </div>	
    </div>	
  )	
}
