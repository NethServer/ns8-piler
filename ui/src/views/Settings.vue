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
          :title="$t('settings.password_warning', { user: 'admin@local' })"
          :description="
            $t('settings.password_warning_description', {
              user: 'admin@local',
              password: 'pilerrocks',
            })
          "
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
          :title="$t('settings.password_warning', { user: 'auditor@local' })"
          :description="
            $t('settings.password_warning_description', {
              user: 'auditor@local',
              password: 'auditor',
            })
          "
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
            v-show="stillLoading"
            heading
            paragraph
            :line-count="10"
            width="80%"
          ></cv-skeleton-text>
          <cv-form
            v-show="!stillLoading"
            @submit.prevent="configureModule"
          >
            <NsTextInput
              :label="$t('settings.piler_fqdn')"
              :placeholder="$t('settings.placeholder_piler_domain')"
              v-model.trim="host"
              :invalid-message="$t(error.host)"
              :disabled="stillLoading"
              ref="host"
            >
            </NsTextInput>
            <NsToggle
              value="letsEncrypt"
              :label="core.$t('apps_lets_encrypt.request_https_certificate')"
              v-model="isLetsEncryptEnabled"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template #tooltip>
                <div class="mg-bottom-sm">
                  {{ core.$t("apps_lets_encrypt.lets_encrypt_tips") }}
                </div>
                <div class="mg-bottom-sm">
                  <cv-link @click="goToCertificates">
                    {{ core.$t("apps_lets_encrypt.go_to_tls_certificates") }}
                  </cv-link>
                </div>
              </template>
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>
            <cv-row v-if="letsEncryptIsEnabled && !isLetsEncryptEnabled">
              <cv-column>
                <NsInlineNotification
                  kind="warning"
                  :title="
                    core.$t('apps_lets_encrypt.lets_encrypt_disabled_warning')
                  "
                  :description="
                    core.$t(
                      'apps_lets_encrypt.lets_encrypt_disabled_warning_description',
                      {
                        node: this.status.node_ui_name
                          ? this.status.node_ui_name
                          : this.status.node,
                      }
                    )
                  "
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <cv-toggle
              value="httpToHttps"
              :label="$t('settings.http_to_https')"
              v-model="isHttpToHttpsEnabled"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </cv-toggle>
            <cv-row v-if="!mail_already_configured && !piler_is_running">
              <cv-column>
                <NsInlineNotification
                  kind="info"
                  :title="$t('settings.warnings_one_time_installation')"
                  :description="
                    $t('settings.warnings_one_time_installation_description')
                  "
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <cv-row v-if="mail_already_configured && !piler_is_running">
              <cv-column>
                <NsInlineNotification
                  kind="warning"
                  :title="$t('settings.the_mail_server_is_already_configured')"
                  :description="
                    $t(
                      'settings.the_mail_server_is_already_configured_description'
                    )
                  "
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
              :disabled="
                stillLoading || (mail_server !== '' && piler_is_running)
              "
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
              :disabled="stillLoading"
              ref="retention_days"
              type="number"
              :helperText="$t('settings.retention_days_helper')"
            >
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
            <cv-row v-if="error.getStatus">
              <cv-column>
                <NsInlineNotification
                  kind="error"
                  :title="$t('action.get-status')"
                  :description="error.getStatus"
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <cv-row v-if="validationErrorDetails.length">
              <cv-column>
                <NsInlineNotification
                  kind="error"
                  :title="core.$t('apps_lets_encrypt.cannot_obtain_certificate')"
                  :description="formattedValidationErrorDetails"
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <NsButton
              kind="primary"
              :icon="Save20"
              :loading="loading.configureModule"
              :disabled="
                stillLoading || (piler_is_running && !always_bcc_correctly_set)
              "
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
      status: {},
      validationErrorDetails: [],
      urlCheckInterval: null,
      host: "",
      mail_server: "",
      mail_server_URL: [],
      piler_is_running: false,
      always_bcc_correctly_set: false,
      is_default_password_admin: false,
      is_default_password_auditor: false,
      isLetsEncryptEnabled: false,
      letsEncryptIsEnabled: false,
      isHttpToHttpsEnabled: false,
      retention_days: "2557",
      mail_already_configured: false,
      loading: {
        getConfiguration: false,
        configureModule: false,
        getStatus: false,
      },
      error: {
        getConfiguration: "",
        configureModule: "",
        host: "",
        lets_encrypt: "",
        http2https: "",
        mail_server: "",
        retention_days: "",
        getStatus: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    stillLoading() {
      return (
        this.loading.getConfiguration ||
        this.loading.configureModule ||
        this.loading.getStatus
      );
    },
    formattedValidationErrorDetails() {
      return this.validationErrorDetails.join("\n");
    },
  },
  created() {
    this.getConfiguration();
    this.getStatus();
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
    mail_server: function () {
      //function to display the warning message if the mail server is already configured
      let server = this.mail_server_URL.find(
        (server) => server.value === this.mail_server
      );
      if (server && server.bcc_set === "not_set") {
        this.mail_already_configured = false;
      } else if (server && server.bcc_set !== "not_set") {
        this.mail_already_configured = true;
      }
    },
  },
  methods: {
    goToCertificates() {
      this.core.$router.push("/settings/tls-certificates");
    },
    async getStatus() {
      this.loading.getStatus = true;
      this.error.getStatus = "";
      const taskAction = "get-status";
      const eventId = this.getUuid();
      // register to task error
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getStatusAborted
      );
      // register to task completion
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getStatusCompleted
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
        this.error.getStatus = this.getErrorMessage(err);
        this.loading.getStatus = false;
        return;
      }
    },
    getStatusAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getStatus = this.$t("error.generic_error");
      this.loading.getStatus = false;
    },
    getStatusCompleted(taskContext, taskResult) {
      this.status = taskResult.output;
      this.loading.getStatus = false;
    },
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
      const label = `${server.ui_name ? server.ui_name : server.module_id} (${
        server.node_name
          ? server.node_name
          : this.$t("settings.node", { nodeId: server.node })
      }): ${
        server.bcc_set === "not_set"
          ? this.$t("settings.not_configured_to_archive")
          : this.$t("settings.configured_to_archive", {
              archive: server.bcc_set,
            })
      }`;
      return {
        name: label,
        label: label,
        value: server.module_uuid,
        bcc_set: server.bcc_set,
      };
    },
    getConfigurationCompleted(taskContext, taskResult) {
      const config = taskResult.output;
      this.host = config.host;
      this.always_bcc_correctly_set = config.always_bcc_correctly_set;
      this.isLetsEncryptEnabled = config.lets_encrypt;
      this.letsEncryptIsEnabled = config.lets_encrypt;
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
      );
      this.loading.getConfiguration = false;
      this.focusElement("host");
    },
    validateConfigureModule() {
      this.clearErrors(this);
      this.validationErrorDetails = [];
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
        if (validationError.details) {
          // show inline error notification with details
          this.validationErrorDetails = validationError.details
            .split("\n")
            .filter((detail) => detail.trim() !== "");
        } else {
          // set i18n error message
          this.error[param] = this.$t("settings." + validationError.error);
          if (!focusAlreadySet) {
            this.focusElement(param);
            focusAlreadySet = true;
          }
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
            mail_server: this.mail_server,
            lets_encrypt: this.isLetsEncryptEnabled,
            http2https: this.isHttpToHttpsEnabled,
            retention_days: parseInt(this.retention_days),
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
