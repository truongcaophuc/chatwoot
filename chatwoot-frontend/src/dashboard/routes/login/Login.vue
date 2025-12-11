<template>
  <div class="flex items-center justify-center min-h-screen bg-gray-100">
    <div class="w-full max-w-md p-8 space-y-6 bg-white rounded shadow-md">
      <h2 class="text-2xl font-bold text-center text-gray-900">Login to Chatwoot</h2>
      <form @submit.prevent="handleLogin" class="space-y-4">
        <div>
          <label for="email" class="block text-sm font-medium text-gray-700">Email</label>
          <input
            v-model="email"
            id="email"
            type="email"
            required
            class="w-full px-3 py-2 mt-1 border rounded-md focus:ring-blue-500 focus:border-blue-500"
            placeholder="dev@chatwoot.com"
          />
        </div>
        <div>
          <label for="password" class="block text-sm font-medium text-gray-700">Password</label>
          <input
            v-model="password"
            id="password"
            type="password"
            required
            class="w-full px-3 py-2 mt-1 border rounded-md focus:ring-blue-500 focus:border-blue-500"
            placeholder="********"
          />
        </div>
        <button
          type="submit"
          class="w-full px-4 py-2 font-medium text-white bg-woot-500 rounded-md hover:bg-woot-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-woot-500"
          style="background-color: #1f93ff;"
        >
          Sign In
        </button>
      </form>
      <div v-if="error" class="text-sm text-center text-red-600">
        {{ error }}
      </div>
      <div class="text-sm text-center text-gray-500">
        (Dev Mode: Click Sign In to simulate login)
      </div>
    </div>
  </div>
</template>

<script>
import { mapMutations } from 'vuex';
import types from '../../store/mutation-types';
import Cookies from 'js-cookie';

export default {
  data() {
    return {
      email: '',
      password: '',
      error: '',
    };
  },
  methods: {
    ...mapMutations({
      setUser: types.SET_CURRENT_USER,
      setUiFlags: types.SET_CURRENT_USER_UI_FLAGS,
    }),
    async handleLogin() {
      // REAL API LOGIN LOGIC
      if (this.email && this.password) {
        try {
          this.error = '';
          const response = await axios.post('/auth/sign_in', {
            email: this.email,
            password: this.password,
          });

          // Update user in store (Chatwoot backend returns user data in response.data.data)
          const userData = response.data.data;
          
          // Fix: Set cookie cw_d_session_info manually to ensure auth persistence on reload
          // Chrome might block HttpOnly cookies from localhost proxy in some cases
          // Extract auth headers from response
          const authHeaders = {
            'access-token': response.headers['access-token'],
            'token-type': response.headers['token-type'],
            client: response.headers['client'],
            expiry: response.headers['expiry'],
            uid: response.headers['uid'],
          };
          
          const sessionInfo = { ...userData, ...authHeaders };
          Cookies.set('cw_d_session_info', JSON.stringify(sessionInfo), { expires: 1, path: '/' });
          
          // Force reload axios headers by updating default headers directly
          // This avoids the need for window.location.reload()
          if (window.axios) {
            Object.assign(window.axios.defaults.headers.common, authHeaders);
          }
          
          this.setUser(userData);
          this.setUiFlags({ isFetching: false });

          // Redirect to dashboard
          // The backend typically sets a cookie, which future requests will include
          // We need to fetch the account ID to redirect correctly if not present in login response
          const accountId = userData.accounts && userData.accounts.length > 0 ? userData.accounts[0].id : null;
          
          if (accountId) {
             this.$router.push({ name: 'home', params: { accountId } });
          } else {
             this.$router.push({ name: 'no_accounts' });
          }

        } catch (err) {
          console.error('Login failed', err);
          this.error = err.response?.data?.errors?.[0] || 'Login failed. Please check your credentials.';
        }
      } else {
        this.error = 'Please enter email and password';
      }
    },
  },
};
</script>
