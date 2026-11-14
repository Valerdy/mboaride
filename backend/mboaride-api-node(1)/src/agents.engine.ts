import crypto from 'node:crypto';
import type { Knex } from 'knex';
import { realtimeHub } from './realtime.js';

export interface RideRequestInput {
    userId: string;
    pickup: { name: string; lat: number; lng: number };
    dropoff: { name: string; lat: number; lng: number };
    windowStart: string;
    windowEnd: string;
    maxPriceFcfa: number;
    comforts: string[];
}

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const R = 6371;
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLng = ((lng2 - lng1) * Math.PI) / 180;
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(a));
}

export class AgentsEngine {
    constructor(private readonly db: Knex) {}

    /**
     * Déclenché lors d'une nouvelle demande passager :
     * 1. Enregistre la demande
     * 2. Cherche un équipage compatible (Agent Matching)
     * 3. Sinon crée un nouvel équipage en attente d'autres passagers/conducteur
     */
    async processPassengerRequest(input: RideRequestInput) {
        const requestId = crypto.randomUUID();

        await this.db('ride_requests').insert({
            id: requestId,
            user_id: input.userId,
            pickup_name: input.pickup.name,
            pickup_lat: input.pickup.lat,
            pickup_lng: input.pickup.lng,
            dropoff_name: input.dropoff.name,
            dropoff_lat: input.dropoff.lat,
            dropoff_lng: input.dropoff.lng,
            window_start: input.windowStart,
            window_end: input.windowEnd,
            max_price_fcfa: input.maxPriceFcfa,
            comforts: JSON.stringify(input.comforts),
            status: 'searching',
        });

        // Recherche des équipages ouverts à Douala
        const candidateCrews = await this.db('crews')
            .whereIn('status', ['forming', 'matched'])
            .orderBy('created_at', 'asc');

        let matchedCrewId: string | null = null;

        for (const crew of candidateCrews) {
            const members = await this.db('ride_requests').where({ crew_id: crew.id });
            if (members.length >= crew.capacity) continue;

            // Agent Spatial : proximité départ <= 2.5 km et arrivée <= 3.0 km
            const originDist = haversineKm(input.pickup.lat, input.pickup.lng, crew.origin_lat, crew.origin_lng);
            const destDist = haversineKm(input.dropoff.lat, input.dropoff.lng, crew.dest_lat, crew.dest_lng);

            // Agent Temporel : écart de fenêtre <= 30 min
            const timeDiffMin =
                Math.abs(new Date(input.windowEnd).getTime() - new Date(crew.departure_target).getTime()) / 60000;

            if (originDist <= 2.5 && destDist <= 3.0 && timeDiffMin <= 30) {
                matchedCrewId = crew.id;
                break;
            }
        }

        if (!matchedCrewId) {
            // Aucun équipage compatible : l'Agent Coordinateur crée un nouvel équipage
            matchedCrewId = crypto.randomUUID();
            await this.db('crews').insert({
                id: matchedCrewId,
                status: 'forming',
                capacity: 4,
                origin_lat: input.pickup.lat,
                origin_lng: input.pickup.lng,
                dest_lat: input.dropoff.lat,
                dest_lng: input.dropoff.lng,
                departure_target: input.windowEnd,
            });
        }

        // Rattache la demande à l'équipage
        const membersBefore = await this.db('ride_requests').where({ crew_id: matchedCrewId });
        const newStatus = membersBefore.length >= 1 ? 'matched' : 'searching';

        await this.db('ride_requests')
            .where({ id: requestId })
            .update({ crew_id: matchedCrewId, status: newStatus });

        const allMembers = await this.db('ride_requests').where({ crew_id: matchedCrewId });

        if (allMembers.length >= 2) {
            await this.db('crews').where({ id: matchedCrewId }).update({ status: 'matched' });
            await this.db('ride_requests').where({ crew_id: matchedCrewId }).update({ status: 'matched' });

            // Notification temps réel à chaque membre de l'équipage
            for (const m of allMembers) {
                realtimeHub.emitToUser(m.user_id, {
                    type: 'crew.matched',
                    crewId: matchedCrewId,
                    requestId: m.id,
                    membersCount: allMembers.length,
                    message: `Équipage formé (${allMembers.length} covoitureurs) vers ${input.dropoff.name} !`,
                });
            }
        } else {
            realtimeHub.emitToUser(input.userId, {
                type: 'request.updated',
                requestId,
                status: 'searching',
                crewId: matchedCrewId,
            });
        }

        return {
            id: requestId,
            crewId: matchedCrewId,
            status: allMembers.length >= 2 ? 'matched' : 'searching',
            membersCount: allMembers.length,
        };
    }

    /**
     * Permet à un conducteur d'accepter / prendre en charge un équipage formé
     */
    async assignDriverToCrew(crewId: string, driverId: string) {
        const crew = await this.db('crews').where({ id: crewId }).first();
        if (!crew) return null;

        await this.db('crews').where({ id: crewId }).update({
            driver_id: driverId,
            status: 'matched',
        });

        const members = await this.db('ride_requests').where({ crew_id: crewId });
        for (const m of members) {
            realtimeHub.emitToUser(m.user_id, {
                type: 'crew.updated',
                crewId,
                status: 'driver_assigned',
                payload: { driverId },
            });
        }
        realtimeHub.emitToCrew(crewId, {
            type: 'crew.updated',
            crewId,
            status: 'driver_assigned',
            payload: { driverId },
        });

        return this.getCrewDetails(crewId);
    }

    async getCrewDetails(crewId: string) {
        const crew = await this.db('crews').where({ id: crewId }).first();
        if (!crew) return null;
        const members = await this.db('ride_requests').where({ crew_id: crewId });
        return { ...crew, members };
    }
}