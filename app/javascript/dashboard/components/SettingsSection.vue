<template>
  <div class="row settings--section">
    <div class="medium-4 small-12">
      <p class="sub-block-title">
        {{ title }}
      </p>
      <p class="sub-head">
        {{ subTitle }}
      </p>
    </div>
    <div class="medium-6 small-12">
      <slot></slot>
    </div>
  </div>
</template>

<script>
export default {
  props: {
    title: {
      type: String,
      required: true,
    },
    subTitle: {
      type: String,
      required: true,
    },
  },
};
</script>

<style lang="scss">
@import '~dashboard/assets/scss/variables';

.settings--section {
  border-bottom: 1px solid $color-border;
  display: flex;
  padding: $space-normal 0;

  .sub-block-title {
    color: $color-woot;
    font-weight: $font-weight-medium;
    margin-bottom: 0;
  }
}
</style>
