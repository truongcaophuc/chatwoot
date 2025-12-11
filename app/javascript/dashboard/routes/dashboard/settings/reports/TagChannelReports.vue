<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportHeader from './components/ReportHeader.vue';
import V4Button from 'dashboard/components-next/button/Button.vue';
import WootDateRangePicker from 'dashboard/components/ui/DateRangePicker.vue';
import {
  downloadCsvFile,
  generateFileName,
} from 'dashboard/helper/downloadHelper';
import ConversationApi from 'dashboard/api/inbox/conversation';
import LabelsAPI from 'dashboard/api/labels';
import InboxesAPI from 'dashboard/api/inboxes';

const { t } = useI18n();

// ===== State =====
const inboxList = ref([]);
const loading = ref(false);
const labels = ref([]);
const rows = ref([]);

const selectedDateRange = ref({
  id: 0,
  name: t('REPORT.DATE_RANGE_OPTIONS.LAST_7_DAYS'),
});
const customDateRange = ref([new Date(), new Date()]);
const isCustomRange = computed(() => selectedDateRange.value.id === 5);

const dateRangeOptions = computed(() => [
  { id: 0, name: t('REPORT.DATE_RANGE_OPTIONS.LAST_7_DAYS') },
  { id: 1, name: t('REPORT.DATE_RANGE_OPTIONS.LAST_30_DAYS') },
  { id: 2, name: t('REPORT.DATE_RANGE_OPTIONS.LAST_3_MONTHS') },
  { id: 3, name: t('REPORT.DATE_RANGE_OPTIONS.LAST_6_MONTHS') },
  { id: 4, name: t('REPORT.DATE_RANGE_OPTIONS.LAST_YEAR') },
  { id: 5, name: t('REPORT.DATE_RANGE_OPTIONS.CUSTOM_DATE_RANGE') },
]);

const from = ref(0);
const to = ref(0);

// ===== Helpers =====
const updateRange = () => {
  const id = selectedDateRange.value.id;
  const now = new Date();
  if (id === 5) {
    const start = customDateRange.value[0];
    const end = customDateRange.value[1];
    from.value = Math.floor(new Date(start.setHours(0, 0, 0, 0)).getTime() / 1000);
    to.value = Math.floor(new Date(end.setHours(23, 59, 59, 999)).getTime() / 1000);
    return;
  }

  const offsets = { 0: 6, 1: 29, 2: 89, 3: 179, 4: 364 };
  const diff = offsets[id] ?? 6;
  const fromDate = new Date(now);
  fromDate.setDate(now.getDate() - diff);
  from.value = Math.floor(new Date(fromDate.setHours(0, 0, 0, 0)).getTime() / 1000);
  to.value = Math.floor(new Date(now.setHours(23, 59, 59, 999)).getTime() / 1000);
};

// Tạo payload filter đúng chuẩn Chatwoot
const buildFilterPayload = () => ({
  payload: [
    {
      attribute_key: 'last_activity_at',
      filter_operator: 'is_greater_than',
      values: [from.value],
      query_operator: 'and',
      attribute_model: 'standard',
    },
    {
      attribute_key: 'last_activity_at',
      filter_operator: 'is_less_than',
      values: [to.value],
      attribute_model: 'standard',
    },
  ],
});

// ===== Fetch data =====
const fetchData = async () => {
  loading.value = true;
  try {
    updateRange();
    const { data } = await ConversationApi.get({ page: 1 });
    const conversations = data?.data?.payload || [];

    const normalizeToSeconds = v => (typeof v === 'number' && v > 2000000000 ? Math.floor(v / 1000) : v);
    const filteredConversations = conversations.filter(conv => {
      const ts = normalizeToSeconds(conv.last_activity_at);
      return ts >= from.value && ts <= to.value;
    });

    // Lấy inbox và labels
    const inboxResp = await InboxesAPI.get();
    inboxList.value = inboxResp?.data?.payload || [];

    const labelsResp = await LabelsAPI.get();
    const labelList = labelsResp?.data?.payload || [];
    labels.value = labelList.map(l => l.title);

    // Map conversation -> label
    const labelMap = {};
    labelList.forEach(lb => { labelMap[lb.title] = lb.title; });

    const pairs = [];
    filteredConversations.forEach(conv => {
      const convLabels = conv.labels || [];
      const inboxId = conv.inbox_id;
      convLabels.forEach(lb => {
        if (labelMap[lb]) pairs.push({ inboxId, label: lb });
      });
    });

    // Build table: channel x label
    rows.value = (inboxList.value || []).map(inb => {
      const counts = {};
      labels.value.forEach(lb => counts[lb] = 0);
      pairs.forEach(p => {
        if (p.inboxId === inb.id) counts[p.label] += 1;
      });
      return { channel: inb.name, counts };
    });

  } finally {
    loading.value = false;
  }
};

// ===== Handlers =====
const onDateSelect = value => {
  selectedDateRange.value = value;
  fetchData();
};
const onCustomRangeChange = value => {
  customDateRange.value = value;
  fetchData();
};

// ===== Download =====
const downloadReports = () => {
  const headers = [t('SUMMARY_REPORTS.INBOX'), ...labels.value];
  const lines = [headers.join(',')];
  rows.value.forEach(r => {
    const rowVals = labels.value.map(lb => String(r.counts[lb] ?? 0));
    lines.push([r.channel, ...rowVals].join(','));
  });
  const fileName = generateFileName({ type: 'label_channel', to: to.value });
  downloadCsvFile(fileName, lines.join('\n'));
};

// Header description
const headerDescription = computed(() => t('SIDEBAR.REPORTS_LABEL_CHANNEL'));

// Mount
onMounted(fetchData);
</script>

<template>
  <ReportHeader
    :header-title="t('SIDEBAR.REPORTS_LABEL_CHANNEL')"
    :header-description="headerDescription"
  >
    <V4Button
      :label="t('LABEL_REPORTS.DOWNLOAD_LABEL_REPORTS')"
      icon="i-ph-download-simple"
      size="sm"
      @click="downloadReports"
    />
  </ReportHeader>

  <div class="grid grid-cols-1 md:grid-cols-3 gap-y-0.5 gap-x-2 mt-3">
    <div class="multiselect-wrap--small">
      <p class="mb-2 text-xs font-medium">{{ t('REPORT.DURATION_FILTER_LABEL') }}</p>
      <multiselect
        v-model="selectedDateRange"
        track-by="name"
        label="name"
        :placeholder="t('FORMS.MULTISELECT.SELECT_ONE')"
        selected-label
        :select-label="t('FORMS.MULTISELECT.ENTER_TO_SELECT')"
        deselect-label=""
        :options="dateRangeOptions"
        :searchable="false"
        :allow-empty="false"
        @select="onDateSelect"
      />
    </div>

    <div v-if="isCustomRange" class="order-3 md:order-4">
      <p class="mb-2 text-xs font-medium">{{ t('REPORT.CUSTOM_DATE_RANGE.PLACEHOLDER') }}</p>
      <WootDateRangePicker
        show-range
        :value="customDateRange"
        :confirm-text="t('REPORT.CUSTOM_DATE_RANGE.CONFIRM')"
        :placeholder="t('REPORT.CUSTOM_DATE_RANGE.PLACEHOLDER')"
        class="auto-width"
        @change="onCustomRangeChange"
      />
    </div>
  </div>

  <div class="flex-1 overflow-auto px-2 py-2 mt-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2">
    <div v-if="loading" class="px-2 py-2 text-n-slate-11">{{ t('REPORT.LOADING_CHART') }}</div>
    <div v-else>
      <table class="w-full">
        <thead>
          <tr>
            <th class="text-left px-2 py-2 font-bold">{{ t('SUMMARY_REPORTS.INBOX') }}</th>
            <th v-for="lb in labels" :key="lb" class="text-left px-2 py-2 font-bold">{{ lb }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in rows" :key="row.channel">
            <td class="px-2 py-2 font-bold">{{ row.channel }}</td>
            <td v-for="lb in labels" :key="lb" class="px-2 py-2">{{ row.counts[lb] }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
