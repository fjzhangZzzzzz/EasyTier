<script setup lang="ts">
import { InputText } from 'primevue';
defineProps<{ urls: string[] }>();
const keys = defineModel<Record<string, string>>({ required: true });
</script>

<template>
    <div v-for="uri in [...new Set(urls)]" :key="uri" class="w-full flex flex-col gap-1">
        <label :for="`peer-key-${uri}`" class="text-sm">{{ uri }} · 节点公钥（可选）</label>
        <InputText :id="`peer-key-${uri}`" v-model="keys[uri]" class="w-full font-mono"
            placeholder="Base64，32 字节；填写后验证对端身份" autocomplete="off" />
    </div>
</template>
