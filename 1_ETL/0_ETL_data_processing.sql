from contextlib import asynccontextmanager
from typing import List, Optional
from fastapi import FastAPI, Depends, HTTPException, Header
from sqlmodel import Field, Session, SQLModel, create_engine, select

# --- 1. DATENBANK SETUP ---
# default=None und primary_key=True signalisieren SQLite, die ID automatisch hochzuzählen
class Artikel(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str
    preis: float

sqlite_url = "sqlite:///datenbank.db"
engine = create_engine(sqlite_url)

# Der moderne Weg: Ein Lifespan-Event für den Start der API
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Alles hier drin passiert BEVOR die API startet
    SQLModel.metadata.create_all(engine)
    yield
    # Alles hiernach passiert WENN die API gestoppt wird

app = FastAPI(lifespan=lifespan)

# --- 2. SICHERHEIT (API-KEY) ---
API_KEY_SECRET = "mein-geheimer-schluessel-123"

def verify_api_key(x_api_key: str = Header(...)):
    if x_api_key != API_KEY_SECRET:
        raise HTTPException(status_code=403, detail="Ungültiger API-Key")
    return x_api_key

# --- 3. ENDPOINTS ---

# Artikel erstellen (Gesichert mit API-Key)
@app.post("/artikel/", response_model=Artikel)
def erstelle_artikel(artikel: Artikel, api_key: str = Depends(verify_api_key)):
    with Session(engine) as session:
        session.add(artikel)
        session.commit()
        session.refresh(artikel)
        return artikel

# Alle Artikel lesen (Öffentlich)
@app.get("/artikel/", response_model=List[Artikel])
def lese_artikel():
    with Session(engine) as session:
        artikel_liste = session.exec(select(Artikel)).all()
        return artikel_liste

# Artikel löschen (Gesichert mit API-Key)
@app.delete("/artikel/{artikel_id}")
def loesche_artikel(artikel_id: int, api_key: str = Depends(verify_api_key)):
    with Session(engine) as session:
        artikel = session.get(Artikel, artikel_id)
        if not artikel:
            raise HTTPException(status_code=404, detail="Nicht gefunden")
        session.delete(artikel)
        session.commit()
        return {"ok": True}