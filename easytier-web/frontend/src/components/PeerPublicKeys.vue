<script setup lang="ts">
import { InputText } from 'primevue';
import { watch } from 'vue';
const props = defineProps<{ urls: string[] }>();
const keys = defineModel<Record<string, string>>({ required: true });
watch(() => [...props.urls], (urls, previous) => {
    const removed = previous.filter(uri => !urls.includes(uri));
    const added = urls.filter(uri => !previous.includes(uri));
    // 编辑一个节点的地址时保留其身份约束；增删和重排不按行号挪用其他节点公钥。
    if (removed.length === 1 && added.length === 1) {
        const key = keys.value[removed[0]];
        if (key?.trim() && !keys.value[added[0]]) keys.value[added[0]] = key;
    }
    for (const uri of Object.keys(keys.value)) {
        if (!urls.includes(uri)) delete keys.value[uri];
    }
});
</script>

<template>
    <div v-for="uri in [...new Set(urls)]" :key="uri" class="w-full flex flex-col gap-1">
        <label :for="`peer-key-${uri}`" class="text-sm">{{ uri }} · 节点公钥（可选）</label>
        <InputText :id="`peer-key-${uri}`" v-model="keys[uri]" class="w-full font-mono"
            placeholder="Base64，32 字节；填写后验证对端身份" autocomplete="off" />
    </div>
</template>
