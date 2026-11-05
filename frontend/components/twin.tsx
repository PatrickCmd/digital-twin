'use client';

import { useState, useRef, useEffect } from 'react';
import Image from 'next/image';
import { Send, Bot, User } from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkBreaks from 'remark-breaks';
import { fetchEventSource } from '@microsoft/fetch-event-source';
import { profile } from '@/content/profile';
import { createId, now } from '@/lib/ids';

interface Message {
    id: string;
    role: 'user' | 'assistant';
    content: string;
    timestamp: Date;
}

export default function Twin() {
    const [messages, setMessages] = useState<Message[]>([]);
    const [input, setInput] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const [sessionId, setSessionId] = useState<string>('');
    const messagesEndRef = useRef<HTMLDivElement>(null);
    const inputRef = useRef<HTMLInputElement>(null);

    const scrollToBottom = () => {
        messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    };

    useEffect(() => {
        scrollToBottom();
    }, [messages]);

    const sendMessage = async (text?: string) => {
        const messageText = (text ?? input).trim();
        if (!messageText || isLoading) return;

        const userMessage: Message = {
            id: createId(),
            role: 'user',
            content: messageText,
            timestamp: now(),
        };

        setMessages(prev => [...prev, userMessage]);
        setInput('');
        setIsLoading(true);

        const assistantMessageId = createId();
        let buffer = '';

        // Add empty assistant message that will be filled by streaming
        setMessages(prev => [...prev, {
            id: assistantMessageId,
            role: 'assistant',
            content: '',
            timestamp: now(),
        }]);

        const controller = new AbortController();

        await fetchEventSource(`${process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000'}/chat/stream`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                message: messageText,
                session_id: sessionId || undefined,
            }),
            signal: controller.signal,
            openWhenHidden: true,
            onmessage(ev) {
                const data = JSON.parse(ev.data);

                if (data.type === 'session') {
                    setSessionId(data.session_id);
                } else if (data.type === 'chunk') {
                    buffer += data.content;
                    setMessages(prev =>
                        prev.map(msg =>
                            msg.id === assistantMessageId
                                ? { ...msg, content: buffer }
                                : msg
                        )
                    );
                } else if (data.type === 'error') {
                    setMessages(prev =>
                        prev.map(msg =>
                            msg.id === assistantMessageId
                                ? { ...msg, content: `Error: ${data.message}` }
                                : msg
                        )
                    );
                }
            },
            onclose() {
                setIsLoading(false);
                setTimeout(() => inputRef.current?.focus(), 100);
            },
            onerror(err) {
                console.error('SSE error:', err);
                setMessages(prev =>
                    prev.map(msg =>
                        msg.id === assistantMessageId && !msg.content
                            ? { ...msg, content: 'Sorry, I encountered an error. Please try again.' }
                            : msg
                    )
                );
                controller.abort();
                setIsLoading(false);
                setTimeout(() => inputRef.current?.focus(), 100);
                throw err; // stop retrying
            },
        });

        setIsLoading(false);
        setTimeout(() => inputRef.current?.focus(), 100);
    };

    const handleKeyPress = (e: React.KeyboardEvent) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
        }
    };

    return (
        <div className="flex flex-col h-full bg-gray-50 rounded-lg shadow-lg">
            {/* Header */}
            <div className="bg-gradient-to-r from-slate-700 to-slate-800 text-white p-4 rounded-t-lg">
                <h2 className="text-xl font-semibold flex items-center gap-2">
                    <Bot className="w-6 h-6" />
                    AI Digital Twin
                </h2>
                <p className="text-sm text-slate-300 mt-1">{profile.full_name}&apos;s AI Digital Twin</p>
            </div>

            {/* Messages */}
            <div className="flex-1 overflow-y-auto p-4 space-y-4">
                {messages.length === 0 && (
                    <div className="text-center text-gray-500 mt-8">
                        <Image
                            src="/avatar.png"
                            alt="Patrick Walukagga"
                            width={80}
                            height={80}
                            className="w-20 h-20 rounded-full mx-auto mb-3 border-2 border-gray-300"
                        />
                        <p>Hello! I&apos;m {profile.full_name}&apos;s Digital Twin.</p>
                        <p className="text-sm mt-2">Ask me anything about {profile.name}, or start with one of these:</p>
                        <ul className="flex flex-wrap justify-center gap-2 mt-4 px-2" aria-label="Suggested questions">
                            {profile.suggested_questions.map((q) => (
                                <li key={q}>
                                    <button
                                        type="button"
                                        onClick={() => sendMessage(q)}
                                        className="px-3 py-1.5 text-sm rounded-full border border-gray-300 bg-white text-gray-700 hover:bg-gray-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600"
                                    >
                                        {q}
                                    </button>
                                </li>
                            ))}
                        </ul>
                    </div>
                )}

                {messages.map((message) => (
                    <div
                        key={message.id}
                        className={`flex gap-3 ${
                            message.role === 'user' ? 'justify-end' : 'justify-start'
                        }`}
                    >
                        {message.role === 'assistant' && (
                            <div className="flex-shrink-0">
                                <Image
                                    src="/avatar.png"
                                    alt=""
                                    width={32}
                                    height={32}
                                    className="w-8 h-8 rounded-full border border-slate-300"
                                />
                            </div>
                        )}

                        <div
                            className={`max-w-[70%] rounded-lg p-3 ${
                                message.role === 'user'
                                    ? 'bg-slate-700 text-white'
                                    : 'bg-white border border-gray-200 text-gray-800'
                            }`}
                        >
                            {message.role === 'assistant' ? (
                                <div className="prose prose-sm max-w-none prose-p:text-gray-800 prose-li:text-gray-800 prose-strong:text-gray-900 prose-headings:text-gray-900 prose-a:text-blue-600 prose-code:text-gray-800 prose-pre:bg-gray-100 prose-pre:text-gray-800 prose-p:my-1 prose-ul:my-1 prose-ol:my-1 prose-li:my-0 prose-headings:my-2 overflow-x-auto break-words">
                                    <ReactMarkdown remarkPlugins={[remarkGfm, remarkBreaks]}>
                                        {message.content}
                                    </ReactMarkdown>
                                </div>
                            ) : (
                                <p className="whitespace-pre-wrap">{message.content}</p>
                            )}
                            <p
                                className={`text-xs mt-1 ${
                                    message.role === 'user' ? 'text-slate-300' : 'text-gray-500'
                                }`}
                            >
                                {message.timestamp.toLocaleTimeString()}
                            </p>
                        </div>

                        {message.role === 'user' && (
                            <div className="flex-shrink-0">
                                <div className="w-8 h-8 bg-gray-600 rounded-full flex items-center justify-center">
                                    <User className="w-5 h-5 text-white" />
                                </div>
                            </div>
                        )}
                    </div>
                ))}

                {isLoading && (
                    <div className="flex gap-3 justify-start">
                        <div className="flex-shrink-0">
                            <Image
                                    src="/avatar.png"
                                    alt=""
                                    width={32}
                                    height={32}
                                    className="w-8 h-8 rounded-full border border-slate-300"
                                />
                        </div>
                        <div className="bg-white border border-gray-200 rounded-lg p-3">
                            <div className="flex space-x-2">
                                <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" />
                                <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce delay-100" />
                                <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce delay-200" />
                            </div>
                        </div>
                    </div>
                )}

                <div ref={messagesEndRef} />
            </div>

            {/* Input */}
            <div className="border-t border-gray-200 p-4 bg-white rounded-b-lg">
                <div className="flex gap-2">
                    <input
                        ref={inputRef}
                        type="text"
                        value={input}
                        onChange={(e) => setInput(e.target.value)}
                        onKeyDown={handleKeyPress}
                        placeholder="Type your message..."
                        className="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-slate-600 focus:border-transparent text-gray-800"
                        disabled={isLoading}
                        autoFocus
                    />
                    <button
                        onClick={() => sendMessage()}
                        disabled={!input.trim() || isLoading}
                        className="px-4 py-2 bg-slate-700 text-white rounded-lg hover:bg-slate-800 focus:outline-none focus:ring-2 focus:ring-slate-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                    >
                        <Send className="w-5 h-5" />
                    </button>
                </div>
            </div>
        </div>
    );
}