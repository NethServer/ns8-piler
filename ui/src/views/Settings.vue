<!--
  Copyright (C) 2022 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("settings.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getConfiguration">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-configuration')"
          :description="error.getConfiguration"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row v-if="is_default_password_admin">
      <cv-column>
        <NsInlineNotification
          kind="warning"
          :title="$t('settings.password_warning', {user:'admin@local'})"
          :description="$t('settings.password_warning_description', {user:'admin@local', password:'pilerrocks'})"
          :showCloseButton="false"
          @click="goToPilerWebapp"
          :actionLabel="$t('settings.open_piler')"
        />
      </cv-column>
    </cv-row>
    <cv-row v-if="is_default_password_auditor">
      <cv-column>
        <NsInlineNotification
          kind="warning"
          :title="$t('settings.password_warning', {user:'auditor@local'})"
          :description="$t('settings.password_warning_description', {user:'auditor@local', password:'auditor'})"
          :showCloseButton="false"
          @click="goToPilerWebapp"
          :actionLabel="$t('settings.open_piler')"
        />
      </cv-column>
    </cv-row>
    <cv-row v-if="piler_is_running && !always_bcc_correctly_set">
      <cv-column>
        <NsInlineNotification
          kind="warning"
          :title="$t('settings.always_bcc_not_set_warning')"
          :description="$t('settings.always_bcc_not_set_description')"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <cv-skeleton-text
            v-show="loading.getConfiguration || loading.configureModule"
            heading
            paragraph
            :line-count="10"
            width="80%"
          ></cv-skeleton-text>
          <cv-form
            v-show="!loading.getConfiguration && !loading.configureModule"
            @submit.prevent="configureModule"
          >
            <NsTextInput
              :label="$t('settings.piler_fqdn')"
              :placeholder="$t('settings.placeholder_piler_domain')"
              v-model.trim="host"
              :invalid-message="$t(error.host)"
              :disabled="loading.getConfiguration || loading.configureModule"
              ref="host"
            >
            </NsTextInput>
            <cv-toggle
              value="letsEncrypt"
              :label="$t('settings.lets_encrypt')"
              v-model="isLetsEncryptEnabled"
              :disabled="loading.getConfiguration || loading.configureModule"
              class="mg-bottom"
            >
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </cv-toggle>
            <cv-toggle
              value="httpToHttps"
              :label="$t('settings.http_to_https')"
              v-model="isHttpToHttpsEnabled"
              :disabled="loading.getConfiguration || loading.configureModule"
              class="mg-bottom"
            >
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </cv-toggle>
            <cv-row v-if="!mail_already_configured && ! piler_is_running">
              <cv-column>
                <NsInlineNotification
                  kind="info"
                  :title="$t('settings.warnings_one_time_installation')"
                  :description="$t('settings.warnings_one_time_installation_description')"
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <cv-row v-if="mail_already_configured && ! piler_is_running">
              <cv-column>
                <NsInlineNotification
                  kind="warning"
                  :title="$t('settings.the_mail_server_is_already_configured')"
                  :description="$t('settings.the_mail_server_is_already_configured_description')"
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <NsComboBox
              v-model.trim="mail_server"
              :autoFilter="true"
              :autoHighlight="true"
              :title="$t('settings.mail_server_fqdn')"
              :label="$t('settings.choose_mail_server')"
              :options="mail_server_URL"
              :userInputLabel="core.$t('settings.choose_mail_server')"
              :acceptUserInput="false"
              :showItemType="true"
              :invalid-message="$t(error.mail_server)"
              :disabled="loading.getConfiguration || loading.configureModule || mail_server !== '' && piler_is_running"
              tooltipAlignment="start"
              tooltipDirection="top"
              ref="mail_server"
            >
              <template slot="tooltip">
                {{ $t("settings.choose_the_mail_server_to_use") }}
              </template>
            </NsComboBox>
            <NsTextInput
              :label="$t('settings.retention_days')"
              :placeholder="$t('settings.placeholder_retention_days')"
              v-model.trim="retention_days"
              :invalid-message="$t(error.retention_days)"
              :disabled="loading.getConfiguration || loading.configureModule"
              ref="retention_days"
              type="number"
              tooltipAlignment="start"
              tooltipDirection="right"
              >
              <template slot="tooltip">
                {{ $t('settings.retention_days_tooltip')}}
              </template>
            </NsTextInput>
            <cv-row v-if="error.configureModule">
              <cv-column>
                <NsInlineNotification
                  kind="error"
                  :title="$t('action.configure-module')"
                  :description="error.configureModule"
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <NsButton
              kind="primary"
              :icon="Save20"
              :loading="loading.configureModule"
              :disabled="loading.getConfiguration || loading.configureModule"
            >
              {{ $t("settings.save") }}
            </NsButton>
          </cv-form>
        </cv-tile>
      </cv-column>
    </cv-row>
  </cv-grid>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";

export default {
  name: "Settings",
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("settings.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "settings",
      },
      urlCheckInterval: null,
      host: "",
      mail_server: "",
      mail_server_URL: [],
      piler_is_running: false,
      always_bcc_correctly_set: false,
      is_default_password_admin: false,
      is_default_password_auditor: false,
      isLetsEncryptEnabled: false,
      isHttpToHttpsEnabled: false,
      retention_days: "2557",
      mail_already_configured: false,
      loading: {
        getConfiguration: false,
        configureModule: false,
      },
      error: {
        getConfiguration: "",
        configureModule: "",
        host: "",
        lets_encrypt: "",
        http2https: "",
        mail_server: "",
        retention_days: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
  },
  created() {
    this.getConfiguration();
  },
  beforeRouteEnter(to, from, next) {
    next((vm) => {
      vm.watchQueryData(vm);
      vm.urlCheckInterval = vm.initUrlBindingForApp(vm, vm.q.page);
    });
  },
  beforeRouteLeave(to, from, next) {
    clearInterval(this.urlCheckInterval);
    next();
  },
watch: {
  mail_server: function() {
    //function to display the warning message if the mail server is already configured
    let server = this.mail_server_URL.find(server => server.value === this.mail_server);
    if (server && server.bcc_not_set) {
      this.mail_already_configured = false;
    } else if (server && !server.bcc_not_set) {
      this.mail_already_configured = true;
    }
  }
},
  methods: {
    goToPilerWebapp() {
      window.open(`https://${this.host}`, "_blank");
    },
    async getConfiguration() {
      this.loading.getConfiguration = true;
      this.error.getConfiguration = "";
      const taskAction = "get-configuration";
      const eventId = this.getUuid();

      // register to task error
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getConfigurationAborted
      );

      // register to task completion
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getConfigurationCompleted
      );

      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];

      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.getConfiguration = this.getErrorMessage(err);
        this.loading.getConfiguration = false;
        return;
      }
    },
    getConfigurationAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getConfiguration = this.$t("error.generic_error");
      this.loading.getConfiguration = false;
    },
    convertToComboboxObject(server) {
      const label = `${server.ui_name ? server.ui_name : server.module_id} (${server.node_name ? server.node_name : this.$t("settings.node", { nodeId: server.node })}): ${this.always_bcc_correctly_set ? this.$t("settings.bound_to_this_archive") :server.bcc_not_set ? this.$t("settings.not_configured_to_archive") : this.$t("settings.configured_to_archive")}`;
      return {
        name: label,
        label: ! this.always_bcc_correctly_set ? this.$t("settings.not_bound_to_a_mail_server") : label,
        value: server.module_uuid,
        bcc_not_set: server.bcc_not_set
      };
    },
    getConfigurationCompleted(taskContext, taskResult) {
      const config = taskResult.output;
      this.host = config.host;
      this.always_bcc_correctly_set = config.always_bcc_correctly_set;
      this.isLetsEncryptEnabled = config.lets_encrypt;
      this.isHttpToHttpsEnabled = config.http2https;
      // force to reload mail_server value after dom update
      this.$nextTick(() => {
        this.mail_server = config.mail_server;
      });
      this.is_default_password_admin = config.is_default_password_admin;
      this.is_default_password_auditor = config.is_default_password_auditor;
      this.piler_is_running = config.piler_is_running;
      this.retention_days = config.retention_days.toString();
      this.mail_server_URL = config.mail_server_URL.map(
          this.convertToComboboxObject
        );;
      this.loading.getConfiguration = false;
      this.focusElement("host");
    },
    validateConfigureModule() {
      this.clearErrors(this);

      let isValidationOk = true;

      if (!this.host) {
        this.error.host = "common.required";

        if (isValidationOk) {
          this.focusElement("host");
        }
        isValidationOk = false;
      }
      if (!this.mail_server) {
        this.error.mail_server = "common.required";

        if (isValidationOk) {
          this.focusElement("mail_server");
        }
        isValidationOk = false;
      }
      if (this.retention_days < 1) {
        this.error.retention_days = "settings.retention_days_error";

        if (isValidationOk) {
          this.focusElement("retention_days");
        }
        isValidationOk = false;
      }
      return isValidationOk;
    },
    configureModuleValidationFailed(validationErrors) {
      this.loading.configureModule = false;
      let focusAlreadySet = false;

      for (const validationError of validationErrors) {
        const param = validationError.parameter;
        // set i18n error message
        this.error[param] = this.$t("settings." + validationError.error);

        if (!focusAlreadySet) {
          this.focusElement(param);
          focusAlreadySet = true;
        }
      }
    },
    async configureModule() {
      const isValidationOk = this.validateConfigureModule();
      if (!isValidationOk) {
        return;
      }

      this.loading.configureModule = true;
      const taskAction = "configure-module";
      const eventId = this.getUuid();

      // register to task error
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.configureModuleAborted
      );

      // register to task validation
      this.core.$root.$once(
        `${taskAction}-validation-failed-${eventId}`,
        this.configureModuleValidationFailed
      );

      // register to task completion
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.configureModuleCompleted
      );

      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data: {
            host: this.host,
            mail_server: this.piler_is_running && !this.always_bcc_correctly_set ? 'ownership_set_by_another_archive' : this.mail_server,
            lets_encrypt: this.isLetsEncryptEnabled,
            http2https: this.isHttpToHttpsEnabled,
            retention_days:  parseInt(this.retention_days),
          },
          extra: {
            title: this.$t("settings.instance_configuration", {
              instance: this.instanceName,
            }),
            description: this.$t("settings.configuring"),
            eventId,
          },
        })
      );
      const err = res[0];

      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.configureModule = this.getErrorMessage(err);
        this.loading.configureModule = false;
        return;
      }
    },
    configureModuleAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.configureModule = this.$t("error.generic_error");
      this.loading.configureModule = false;
    },
    configureModuleCompleted() {
      window.location.reload();
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";
.mg-bottom {
  margin-bottom: $spacing-06;
}
</style>
