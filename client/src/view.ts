import { writable } from "svelte/store";

export type Tab = "alarms" | "new" | "join";
export const activeTab = writable<Tab>("alarms");
