# AGENT.md — FastAPI + Tailwind CSS + shadcn/ui Application

> Comprehensive reference for AI coding agents building full-stack applications with FastAPI (Python backend) and a React/Next.js frontend using Tailwind CSS and shadcn/ui.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Stack & Versions](#stack--versions)
3. [Project Structure](#project-structure)
4. [Environment Setup](#environment-setup)
5. [Backend — FastAPI](#backend--fastapi)
6. [Frontend — React + Tailwind + shadcn/ui](#frontend--react--tailwind--shadcnui)
7. [API Integration Patterns](#api-integration-patterns)
8. [Authentication](#authentication)
9. [Database Patterns](#database-patterns)
10. [State Management](#state-management)
11. [Forms & Validation](#forms--validation)
12. [Error Handling](#error-handling)
13. [Testing](#testing)
14. [Code Style & Conventions](#code-style--conventions)
15. [Common Pitfalls](#common-pitfalls)
16. [Commands Reference](#commands-reference)

---

## Project Overview

This is a full-stack web application using:
- **Backend**: FastAPI (Python) — REST API with automatic OpenAPI docs
- **Frontend**: React (Next.js App Router) — UI layer
- **Styling**: Tailwind CSS — utility-first CSS
- **Components**: shadcn/ui — accessible, unstyled component primitives built on Radix UI

The backend and frontend are **separate applications** that communicate over HTTP/JSON.

---

## Stack & Versions

| Layer        | Technology          | Version  |
|--------------|---------------------|----------|
| Backend      | Python              | 3.11+    |
| Backend      | FastAPI             | 0.110+   |
| Backend      | Pydantic            | v2       |
| Backend      | SQLAlchemy          | 2.0+     |
| Backend      | Alembic             | 1.13+    |
| Backend      | uvicorn             | 0.29+    |
| Frontend     | Node.js             | 20+      |
| Frontend     | Next.js             | 14+ (App Router) |
| Frontend     | React               | 18+      |
| Frontend     | TypeScript          | 5+       |
| Styling      | Tailwind CSS        | 3.4+     |
| Components   | shadcn/ui           | latest   |
| Components   | Radix UI            | (via shadcn) |
| HTTP Client  | axios / fetch       | —        |
| Validation   | Zod (frontend)      | 3+       |
| Validation   | Pydantic (backend)  | v2       |

---

## Project Structure

```
my-app/
├── backend/                    # FastAPI application
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py             # App entry point, middleware, router registration
│   │   ├── config.py           # Settings via pydantic-settings
│   │   ├── dependencies.py     # Shared FastAPI dependencies (db session, current user)
│   │   ├── models/             # SQLAlchemy ORM models
│   │   │   ├── __init__.py
│   │   │   └── user.py
│   │   ├── schemas/            # Pydantic request/response schemas
│   │   │   ├── __init__.py
│   │   │   └── user.py
│   │   ├── routers/            # Route handlers grouped by feature
│   │   │   ├── __init__.py
│   │   │   ├── auth.py
│   │   │   └── users.py
│   │   ├── services/           # Business logic (no direct DB/HTTP here ideally)
│   │   │   └── user_service.py
│   │   ├── crud/               # Database CRUD operations
│   │   │   └── user.py
│   │   └── db/
│   │       ├── base.py         # SQLAlchemy Base
│   │       └── session.py      # DB engine + SessionLocal
│   ├── alembic/                # Database migrations
│   │   ├── env.py
│   │   └── versions/
│   ├── tests/
│   │   ├── conftest.py
│   │   └── test_users.py
│   ├── alembic.ini
│   ├── pyproject.toml          # or requirements.txt
│   └── .env
│
├── frontend/                   # Next.js application
│   ├── src/
│   │   ├── app/                # Next.js App Router
│   │   │   ├── layout.tsx
│   │   │   ├── page.tsx
│   │   │   ├── (auth)/
│   │   │   │   ├── login/page.tsx
│   │   │   │   └── register/page.tsx
│   │   │   └── dashboard/
│   │   │       └── page.tsx
│   │   ├── components/
│   │   │   ├── ui/             # shadcn/ui generated components (DO NOT EDIT)
│   │   │   │   ├── button.tsx
│   │   │   │   ├── input.tsx
│   │   │   │   └── ...
│   │   │   ├── layout/         # App layout components
│   │   │   │   ├── header.tsx
│   │   │   │   └── sidebar.tsx
│   │   │   └── features/       # Feature-specific components
│   │   │       └── users/
│   │   │           └── user-table.tsx
│   │   ├── lib/
│   │   │   ├── api.ts          # Axios instance / fetch wrapper
│   │   │   ├── utils.ts        # cn() helper + misc utilities
│   │   │   └── validators.ts   # Zod schemas
│   │   ├── hooks/              # Custom React hooks
│   │   │   └── use-users.ts
│   │   ├── types/              # TypeScript interfaces / API types
│   │   │   └── index.ts
│   │   └── store/              # Zustand or Context state
│   ├── public/
│   ├── components.json         # shadcn/ui config
│   ├── tailwind.config.ts
│   ├── tsconfig.json
│   ├── next.config.ts
│   ├── package.json
│   └── .env.local
│
├── docker-compose.yml          # Local dev orchestration
└── README.md
```

---

## Environment Setup

### Backend `.env`

```env
# backend/.env
DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/myapp
SECRET_KEY=your-super-secret-key-change-in-production
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
CORS_ORIGINS=["http://localhost:3000"]
ENVIRONMENT=development
```

### Frontend `.env.local`

```env
# frontend/.env.local
NEXT_PUBLIC_API_URL=http://localhost:8000
```

### Backend Setup

```bash
cd backend
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -e ".[dev]"          # or: pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --reload --port 8000
```

### Frontend Setup

```bash
cd frontend
npm install
npx shadcn@latest init           # First time only
npm run dev                      # http://localhost:3000
```

---

## Backend — FastAPI

### `app/main.py` — Entry Point

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.routers import auth, users

app = FastAPI(
    title="My App API",
    version="1.0.0",
    docs_url="/docs" if settings.ENVIRONMENT != "production" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(users.router, prefix="/api/users", tags=["users"])

@app.get("/health")
async def health_check():
    return {"status": "ok"}
```

### `app/config.py` — Settings

```python
from pydantic_settings import BaseSettings
from typing import List

class Settings(BaseSettings):
    DATABASE_URL: str
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    CORS_ORIGINS: List[str] = ["http://localhost:3000"]
    ENVIRONMENT: str = "development"

    class Config:
        env_file = ".env"

settings = Settings()
```

### `app/db/session.py` — Database Session

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from app.config import settings

engine = create_async_engine(settings.DATABASE_URL, echo=False)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)

async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

### `app/dependencies.py` — Shared Dependencies

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.services.auth_service import decode_token
from app.crud import user as user_crud

security = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
):
    token = credentials.credentials
    user_id = decode_token(token)
    user = await user_crud.get(db, id=user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user
```

### Pydantic v2 Schemas

```python
# app/schemas/user.py
from pydantic import BaseModel, EmailStr, ConfigDict
from datetime import datetime
from uuid import UUID

class UserBase(BaseModel):
    email: EmailStr
    full_name: str

class UserCreate(UserBase):
    password: str

class UserUpdate(BaseModel):
    full_name: str | None = None
    email: EmailStr | None = None

class UserRead(UserBase):
    id: UUID
    created_at: datetime
    is_active: bool

    model_config = ConfigDict(from_attributes=True)
```

### Router Pattern

```python
# app/routers/users.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.dependencies import get_current_user
from app.schemas.user import UserRead, UserCreate
from app.crud import user as user_crud

router = APIRouter()

@router.get("/me", response_model=UserRead)
async def get_me(current_user=Depends(get_current_user)):
    return current_user

@router.get("/{user_id}", response_model=UserRead)
async def get_user(
    user_id: str,
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    user = await user_crud.get(db, id=user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@router.post("/", response_model=UserRead, status_code=status.HTTP_201_CREATED)
async def create_user(
    payload: UserCreate,
    db: AsyncSession = Depends(get_db),
):
    existing = await user_crud.get_by_email(db, email=payload.email)
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    return await user_crud.create(db, obj_in=payload)
```

### CRUD Base Pattern

```python
# app/crud/base.py
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import TypeVar, Generic, Type
from pydantic import BaseModel
from app.db.base import Base

ModelType = TypeVar("ModelType", bound=Base)
CreateSchemaType = TypeVar("CreateSchemaType", bound=BaseModel)

class CRUDBase(Generic[ModelType, CreateSchemaType]):
    def __init__(self, model: Type[ModelType]):
        self.model = model

    async def get(self, db: AsyncSession, id: any) -> ModelType | None:
        result = await db.execute(select(self.model).where(self.model.id == id))
        return result.scalar_one_or_none()

    async def get_multi(self, db: AsyncSession, *, skip=0, limit=100):
        result = await db.execute(select(self.model).offset(skip).limit(limit))
        return result.scalars().all()

    async def create(self, db: AsyncSession, *, obj_in: CreateSchemaType) -> ModelType:
        obj = self.model(**obj_in.model_dump())
        db.add(obj)
        await db.flush()
        await db.refresh(obj)
        return obj

    async def delete(self, db: AsyncSession, *, id: any) -> ModelType | None:
        obj = await self.get(db, id)
        if obj:
            await db.delete(obj)
        return obj
```

---

## Frontend — React + Tailwind + shadcn/ui

### `components.json` — shadcn/ui Config

```json
{
  "$schema": "https://ui.shadcn.com/schema.json",
  "style": "default",
  "rsx": false,
  "tsx": true,
  "tailwind": {
    "config": "tailwind.config.ts",
    "css": "src/app/globals.css",
    "baseColor": "slate",
    "cssVariables": true,
    "prefix": ""
  },
  "aliases": {
    "components": "@/components",
    "utils": "@/lib/utils",
    "ui": "@/components/ui",
    "lib": "@/lib",
    "hooks": "@/hooks"
  }
}
```

### `tailwind.config.ts`

```ts
import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: ["class"],
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: {
          DEFAULT: "hsl(var(--primary))",
          foreground: "hsl(var(--primary-foreground))",
        },
        secondary: {
          DEFAULT: "hsl(var(--secondary))",
          foreground: "hsl(var(--secondary-foreground))",
        },
        destructive: {
          DEFAULT: "hsl(var(--destructive))",
          foreground: "hsl(var(--destructive-foreground))",
        },
        muted: {
          DEFAULT: "hsl(var(--muted))",
          foreground: "hsl(var(--muted-foreground))",
        },
        accent: {
          DEFAULT: "hsl(var(--accent))",
          foreground: "hsl(var(--accent-foreground))",
        },
        card: {
          DEFAULT: "hsl(var(--card))",
          foreground: "hsl(var(--card-foreground))",
        },
      },
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
};

export default config;
```

### `lib/utils.ts` — The `cn()` Helper

```ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

// Always use cn() to combine Tailwind classes — it handles conflicts correctly
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

### Installing shadcn/ui Components

```bash
# Add individual components as needed
npx shadcn@latest add button
npx shadcn@latest add input
npx shadcn@latest add form
npx shadcn@latest add card
npx shadcn@latest add dialog
npx shadcn@latest add table
npx shadcn@latest add toast
npx shadcn@latest add dropdown-menu
npx shadcn@latest add select
npx shadcn@latest add badge
npx shadcn@latest add separator
npx shadcn@latest add sheet
npx shadcn@latest add skeleton
npx shadcn@latest add avatar
npx shadcn@latest add alert
```

> **Rule**: Files in `src/components/ui/` are generated by shadcn and should not be modified manually. Override behavior by wrapping components.

### Using shadcn/ui Components

```tsx
// Correct: import from @/components/ui/
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export function LoginCard() {
  return (
    <Card className="w-full max-w-md">
      <CardHeader>
        <CardTitle>Sign In</CardTitle>
        <CardDescription>Enter your credentials to continue</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <Input type="email" placeholder="Email" />
        <Input type="password" placeholder="Password" />
        <Button className="w-full">Sign In</Button>
      </CardContent>
    </Card>
  );
}
```

### Tailwind Class Conventions

```tsx
// Layout
<div className="flex items-center justify-between gap-4">
<div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">

// Spacing scale: use multiples of 4 (1=4px, 2=8px, 4=16px, 6=24px, 8=32px)
<div className="p-6 mt-4 mb-8">

// Responsive
<h1 className="text-2xl md:text-4xl font-bold">

// State variants
<button className="bg-primary hover:bg-primary/90 disabled:opacity-50 transition-colors">

// Dark mode (if enabled)
<div className="bg-white dark:bg-gray-900 text-gray-900 dark:text-gray-100">

// NEVER use arbitrary values unless absolutely necessary
// Bad:  className="mt-[13px]"
// Good: className="mt-3"   (or mt-4 if possible)
```

---

## API Integration Patterns

### `lib/api.ts` — Axios Instance

```ts
import axios from "axios";

export const api = axios.create({
  baseURL: process.env.NEXT_PUBLIC_API_URL,
  headers: { "Content-Type": "application/json" },
  withCredentials: true,
});

// Attach auth token from storage
api.interceptors.request.use((config) => {
  const token = localStorage.getItem("access_token");
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

// Global error handling
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem("access_token");
      window.location.href = "/login";
    }
    return Promise.reject(error);
  }
);
```

### `types/index.ts` — API Types

```ts
// Mirror your Pydantic schemas here
export interface User {
  id: string;
  email: string;
  full_name: string;
  is_active: boolean;
  created_at: string;
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  size: number;
  pages: number;
}

export interface ApiError {
  detail: string | { msg: string; type: string }[];
}
```

### Custom Hook Pattern

```ts
// hooks/use-users.ts
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api";
import type { User } from "@/types";

export function useUsers() {
  return useQuery({
    queryKey: ["users"],
    queryFn: async () => {
      const { data } = await api.get<User[]>("/api/users");
      return data;
    },
  });
}

export function useCreateUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (payload: { email: string; full_name: string; password: string }) => {
      const { data } = await api.post<User>("/api/users", payload);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
    },
  });
}
```

---

## Authentication

### Backend — JWT Auth

```python
# app/services/auth_service.py
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
from passlib.context import CryptContext
from app.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)

def create_access_token(subject: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    return jwt.encode({"sub": subject, "exp": expire}, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

def decode_token(token: str) -> str:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        return payload["sub"]
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")
```

### Frontend — Auth Context

```tsx
// store/auth-context.tsx
"use client";
import { createContext, useContext, useState, useEffect } from "react";
import { api } from "@/lib/api";
import type { User } from "@/types";

interface AuthContextType {
  user: User | null;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
  isLoading: boolean;
}

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const token = localStorage.getItem("access_token");
    if (token) {
      api.get<User>("/api/users/me")
        .then(({ data }) => setUser(data))
        .catch(() => localStorage.removeItem("access_token"))
        .finally(() => setIsLoading(false));
    } else {
      setIsLoading(false);
    }
  }, []);

  const login = async (email: string, password: string) => {
    const form = new URLSearchParams({ username: email, password });
    const { data } = await api.post<{ access_token: string }>("/api/auth/token", form, {
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
    });
    localStorage.setItem("access_token", data.access_token);
    const { data: me } = await api.get<User>("/api/users/me");
    setUser(me);
  };

  const logout = () => {
    localStorage.removeItem("access_token");
    setUser(null);
  };

  return (
    <AuthContext.Provider value={{ user, login, logout, isLoading }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
};
```

---

## Database Patterns

### SQLAlchemy 2.0 Model

```python
# app/models/user.py
from sqlalchemy import String, Boolean, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column
from uuid import UUID, uuid4
from app.db.base import Base

class User(Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(255))
    hashed_password: Mapped[str] = mapped_column(String(255))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), onupdate=func.now(), nullable=True)
```

### Alembic Migration Workflow

```bash
# Create a new migration after changing models
alembic revision --autogenerate -m "add users table"

# Apply migrations
alembic upgrade head

# Rollback one step
alembic downgrade -1

# Check current revision
alembic current
```

---

## State Management

Use **React Query** (TanStack Query) for server state and **Zustand** or Context for client/UI state.

```bash
npm install @tanstack/react-query zustand
```

```tsx
// app/layout.tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
const queryClient = new QueryClient();

export default function RootLayout({ children }) {
  return (
    <html>
      <body>
        <QueryClientProvider client={queryClient}>
          {children}
        </QueryClientProvider>
      </body>
    </html>
  );
}
```

---

## Forms & Validation

Use **React Hook Form** + **Zod** + **shadcn/ui Form** components together.

```bash
npm install react-hook-form zod @hookform/resolvers
npx shadcn@latest add form
```

```tsx
"use client";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";

const loginSchema = z.object({
  email: z.string().email("Invalid email address"),
  password: z.string().min(8, "Password must be at least 8 characters"),
});

type LoginFormValues = z.infer<typeof loginSchema>;

export function LoginForm() {
  const form = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: "", password: "" },
  });

  const onSubmit = async (values: LoginFormValues) => {
    // call API here
    console.log(values);
  };

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
        <FormField
          control={form.control}
          name="email"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Email</FormLabel>
              <FormControl>
                <Input placeholder="you@example.com" {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="password"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Password</FormLabel>
              <FormControl>
                <Input type="password" {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <Button type="submit" className="w-full" disabled={form.formState.isSubmitting}>
          {form.formState.isSubmitting ? "Signing in..." : "Sign In"}
        </Button>
      </form>
    </Form>
  );
}
```

---

## Error Handling

### Backend — Consistent Error Responses

```python
# app/main.py — add custom exception handlers
from fastapi import Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content={"detail": exc.errors()},
    )
```

### Frontend — Toast Notifications

```tsx
// Use shadcn/ui toast for user-facing errors
import { useToast } from "@/hooks/use-toast";  // generated by shadcn

function MyComponent() {
  const { toast } = useToast();

  const handleSubmit = async () => {
    try {
      await someApiCall();
      toast({ title: "Success", description: "Action completed." });
    } catch (err: any) {
      toast({
        variant: "destructive",
        title: "Error",
        description: err.response?.data?.detail ?? "Something went wrong.",
      });
    }
  };
}
```

---

## Testing

### Backend — pytest + httpx

```bash
pip install pytest pytest-asyncio httpx
```

```python
# tests/conftest.py
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from app.main import app
from app.db.session import get_db
from app.db.base import Base

TEST_DB_URL = "sqlite+aiosqlite:///:memory:"

@pytest.fixture(scope="session")
async def db_engine():
    engine = create_async_engine(TEST_DB_URL)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()

@pytest.fixture
async def client(db_engine):
    session_factory = async_sessionmaker(db_engine)
    async def override_get_db():
        async with session_factory() as session:
            yield session
    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c

# tests/test_users.py
@pytest.mark.asyncio
async def test_create_user(client):
    resp = await client.post("/api/users", json={
        "email": "test@example.com",
        "full_name": "Test User",
        "password": "secret1234",
    })
    assert resp.status_code == 201
    assert resp.json()["email"] == "test@example.com"
```

### Frontend — Vitest + Testing Library

```bash
npm install -D vitest @testing-library/react @testing-library/user-event jsdom
```

```tsx
// components/features/users/__tests__/user-table.test.tsx
import { render, screen } from "@testing-library/react";
import { UserTable } from "../user-table";

const mockUsers = [{ id: "1", email: "a@b.com", full_name: "Alice", is_active: true, created_at: "" }];

test("renders user rows", () => {
  render(<UserTable users={mockUsers} />);
  expect(screen.getByText("Alice")).toBeInTheDocument();
});
```

---

## Code Style & Conventions

### Naming

| Entity                | Convention          | Example                  |
|-----------------------|---------------------|--------------------------|
| Python files          | snake_case          | `user_service.py`        |
| Python functions      | snake_case          | `get_current_user()`     |
| Python classes        | PascalCase          | `UserCreate`             |
| TS/React files        | kebab-case          | `user-table.tsx`         |
| React components      | PascalCase          | `UserTable`              |
| React hooks           | camelCase + use     | `useUsers()`             |
| API routes            | kebab-case          | `/api/user-profiles`     |
| DB tables             | snake_case plural   | `users`, `access_tokens` |
| Env variables         | SCREAMING_SNAKE     | `DATABASE_URL`           |

### Python Rules
- All FastAPI route functions must be `async`
- Use Pydantic v2 syntax (`model_config`, `model_dump()` not `dict()`)
- Type-hint everything — FastAPI relies on type hints for validation
- Keep routers thin: business logic lives in services, DB logic in CRUD
- Always use `response_model=` on route decorators

### TypeScript Rules
- No `any` unless wrapping unknown API errors
- Prefer `interface` for API types, `type` for unions/utility types
- All API types must mirror their Pydantic schema equivalents
- Server Components by default; add `"use client"` only when needed
- Never import from `@/components/ui/*` inside other `ui/` files

### Tailwind Rules
- Use `cn()` for all conditional class application
- Mobile-first breakpoints: `sm:`, `md:`, `lg:`, `xl:`
- Use CSS variables (via shadcn) for theme colors, never hardcode hex in Tailwind
- Extract repeated class combinations into components, not `@apply`

---

## Common Pitfalls

| Problem | Cause | Fix |
|---|---|---|
| CORS errors in dev | Backend not allowing `localhost:3000` | Check `CORS_ORIGINS` in `.env` and `CORSMiddleware` |
| 422 Unprocessable Entity | Pydantic validation failure | Check request body matches schema; log `exc.errors()` |
| shadcn component not found | Not installed | Run `npx shadcn@latest add <component>` |
| Tailwind classes not applying | File not in `content` glob | Add path to `tailwind.config.ts` content array |
| `cn()` not merging correctly | Missing `tailwind-merge` | `npm install tailwind-merge clsx` |
| Async SQLAlchemy DetachedInstanceError | Accessing lazy relationship outside session | Use `selectinload()` or `joinedload()` in query |
| JWT 401 on valid token | Clock skew or wrong `SECRET_KEY` | Verify env var is loaded; check token expiry |
| Next.js hydration mismatch | Server/client render differ | Move localStorage access to `useEffect` |
| React Query stale data | Not invalidating after mutation | Call `queryClient.invalidateQueries()` in `onSuccess` |
| Form not validating | Missing `zodResolver` | Pass `resolver: zodResolver(schema)` to `useForm` |

---

## Commands Reference

### Backend

```bash
# Dev server
uvicorn app.main:app --reload --port 8000

# Run tests
pytest -v

# Run tests with coverage
pytest --cov=app --cov-report=term-missing

# Format & lint
ruff check . --fix
ruff format .
mypy app/

# DB migrations
alembic revision --autogenerate -m "description"
alembic upgrade head
alembic downgrade -1
```

### Frontend

```bash
# Dev server
npm run dev

# Build
npm run build

# Type check
npx tsc --noEmit

# Lint
npm run lint

# Run tests
npm run test

# Add shadcn component
npx shadcn@latest add <component-name>

# Update all shadcn components
npx shadcn@latest diff
```

### Docker

```bash
# Start all services
docker compose up -d

# Rebuild after dependency changes
docker compose up -d --build

# View logs
docker compose logs -f backend

# Stop
docker compose down
```

---

*This AGENT.md is the single source of truth for how this codebase is structured and how to work within it. When in doubt, follow the patterns here.*