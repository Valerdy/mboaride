import type { Response } from 'express';

export type RealtimeEvent =
    | { type: 'request.updated'; requestId: string; status: string; crewId?: string }
    | { type: 'crew.matched'; crewId: string; requestId: string; membersCount: number; message: string }
    | { type: 'crew.updated'; crewId: string; status: string; payload?: unknown };

class RealtimeHub {
    private userClients = new Map<string, Set<Response>>();
    private crewClients = new Map<string, Set<Response>>();

    subscribeUser(userId: string, res: Response): () => void {
        if (!this.userClients.has(userId)) this.userClients.set(userId, new Set());
        this.userClients.get(userId)!.add(res);

        return () => {
            this.userClients.get(userId)?.delete(res);
        };
    }

    subscribeCrew(crewId: string, res: Response): () => void {
        if (!this.crewClients.has(crewId)) this.crewClients.set(crewId, new Set());
        this.crewClients.get(crewId)!.add(res);

        return () => {
            this.crewClients.get(crewId)?.delete(res);
        };
    }

    emitToUser(userId: string, event: RealtimeEvent): void {
        const clients = this.userClients.get(userId);
        if (!clients) return;
        const frame = `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`;
        for (const res of clients) {
            res.write(frame);
        }
    }

    emitToCrew(crewId: string, event: RealtimeEvent): void {
        const clients = this.crewClients.get(crewId);
        if (!clients) return;
        const frame = `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`;
        for (const res of clients) {
            res.write(frame);
        }
    }
}

export const realtimeHub = new RealtimeHub();