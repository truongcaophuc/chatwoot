<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportHeader from './components/ReportHeader.vue';
import V4Button from 'dashboard/components-next/button/Button.vue';
import ReportFilterSelector from './components/FilterSelector.vue';
import Spinner from 'shared/components/Spinner.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import {
  downloadCsvFile,
  generateFileName,
} from 'dashboard/helper/downloadHelper';
import ConversationApi from 'dashboard/api/inbox/conversation';
import LabelsAPI from 'dashboard/api/labels';
import InboxesAPI from 'dashboard/api/inboxes';
import { useTrack } from 'dashboard/composables';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import { GROUP_BY_FILTER } from './constants';
import { useStore } from 'vuex';

const { t } = useI18n();
const store = useStore();

// ===== State =====
const inboxList = ref([]);
const loading = ref(false);
const labels = ref([]);
const rows = ref([]);
const currentPage = ref(1);
const itemsPerPage = 10;

// Date range controlled via ReportFilterSelector

const from = ref(0);
const to = ref(0);
const groupBy = ref(GROUP_BY_FILTER[1]);
const businessHours = ref(false);

// ===== Helpers =====

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
    await store.dispatch('conversationPage/reset');
    await store.dispatch('emptyAllConversations');
    await store.dispatch('fetchFilteredConversations', {
      queryData: buildFilterPayload(),
      page: 1,
    });
    const filteredConversations = store.getters.getAllConversations || [];

    const inboxResp = await InboxesAPI.get();
    inboxList.value = inboxResp?.data?.payload || [];

    const labelsResp = await LabelsAPI.get();
    const labelList = labelsResp?.data?.payload || [];
    labels.value = labelList.map(l => l.title);

    const labelMap = {};
    labelList.forEach(lb => {
      labelMap[lb.title] = lb.title;
    });

    const pairs = [];
    filteredConversations.forEach(conv => {
      const convLabels = conv.labels || [];
      const inboxId = conv.inbox_id;
      convLabels.forEach(lb => {
        if (labelMap[lb]) pairs.push({ inboxId, label: lb });
      });
    });

    rows.value = (inboxList.value || []).map(inb => {
      const counts = {};
      labels.value.forEach(lb => (counts[lb] = 0));
      pairs.forEach(p => {
        if (p.inboxId === inb.id) counts[p.label] += 1;
      });
      return { channel: inb.name, counts };
    });

    if (currentPage.value > Math.ceil(rows.value.length / itemsPerPage)) {
      currentPage.value = 1;
    }
  } finally {
    loading.value = false;
  }
};

const fetchAllData = async () => {
  await fetchData();
};

const totalPages = computed(
  () => Math.ceil(rows.value.length / itemsPerPage) || 1
);
const paginatedRows = computed(() => {
  const start = (currentPage.value - 1) * itemsPerPage;
  return rows.value.slice(start, start + itemsPerPage);
});

// ===== Handlers =====
const onFilterChange = ({ from: newFrom, to: newTo, groupBy: newGroupBy, businessHours: newBusinessHours }) => {
  from.value = newFrom;
  to.value = newTo;
  groupBy.value = newGroupBy;
  businessHours.value = newBusinessHours;
  fetchAllData();
  useTrack(REPORTS_EVENTS.FILTER_REPORT, {
    filterValue: { from: newFrom, to: newTo, groupBy: newGroupBy, businessHours: newBusinessHours },
    reportType: 'conversations',
  });
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
onMounted(fetchAllData);
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
  <div class="mt-3">
    <ReportFilterSelector
      :show-agents-filter="false"
      show-group-by-filter
      @filter-change="onFilterChange"
    />
  </div>

  <div
    class="flex-1 px-2 py-2 mt-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <div v-if="loading" class="h-32 flex items-center justify-center">
      <Spinner />
    </div>
    <div v-else>
      <div class="overflow-x-auto">
        <table class="w-full">
          <thead>
            <tr>
              <th
                class="sticky top-0 left-0 z-30 px-2 py-2 bg-n-slate-3 corner-header"
              >
                <div class="corner-content">
                  <span class="corner-top-right">Labels</span>
                  <span class="corner-bottom-left">{{
                    t('SUMMARY_REPORTS.INBOX')
                  }}</span>
                </div>
              </th>
              <th
                v-for="lb in labels"
                :key="lb"
                class="sticky top-0 z-10 text-center px-2 py-2 font-medium bg-n-slate-3 min-w-[10rem]"
              >
                {{ lb }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in paginatedRows" :key="row.channel">
              <td class="sticky left-0 z-20 px-2 py-2 font-medium min-w-[12rem] bg-white">
                {{ row.channel }}
              </td>
              <td
                v-for="lb in labels"
                :key="lb"
                class="px-2 py-2 min-w-[10rem] text-center"
              >
                {{ row.counts[lb] }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="mt-3">
        <PaginationFooter
          :current-page="currentPage"
          :total-items="rows.length"
          :items-per-page="itemsPerPage"
          @update:currentPage="currentPage = $event"
        />
      </div>
    </div>
  </div>
</template>

<style>
.corner-header {
  position: sticky;
}
.corner-content {
  position: relative;
  width: 100%;
  height: 100%;
  min-height: 2.25rem;
}
.corner-header::after {
  content: '';
  position: absolute;
  inset: 0;
background: linear-gradient(
  225deg,
  transparent calc(50% - 2px),
  rgb(191, 191, 191) 50%,
  transparent calc(50% + 2px)
);
  pointer-events: none;
}
.corner-top-right {
  position: absolute;
  top: 0.25rem;
  right: 0.5rem;
  font-size: 0.8rem;
  font-weight: 700;
}
.corner-bottom-left {
  position: absolute;
  bottom: 0.25rem;
  left: 0.5rem;
  font-size: 0.8rem;
  font-weight: 700;
}
</style>
